import SwiftUI
import UserNotifications
import Sparkle
import Combine

/// Main app entry point. Uses a Settings scene with an empty view since this is a
/// menu-bar-only app (LSUIElement = true in Info.plist hides it from the Dock).
/// All real setup happens in AppDelegate.
@main
struct MenuBarPopoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Central orchestrator that wires all services together and manages the app lifecycle.
///
/// Responsibilities:
/// - Creates and connects all services (BLE, MQTT, HTTP API, Notion sync)
/// - Sets up the callback chain: BLE → Workout → Notion / MQTT
/// - Manages the status bar item and popover UI
/// - Handles sleep/wake notifications to pause and resume services
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var workout = Workout()
    private var walkingPadService: WalkingPadService
    private var bluetoothDiscoverService: BluetoothDiscoveryService
    private var updateTimer: RepeatingTimer? = nil;
    private var mqttService: MqttService
    var notionService: NotionService { NotionService.shared }
    var stravaService: StravaService { StravaService.shared }

    static let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    var statusBarItem: NSStatusItem!
    private var popover: NSPopover!
    /// Right-click menu on the status item (Quit).
    private var contextMenu: NSMenu!
    private var goalObserver: AnyCancellable?

    static func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    override init() {
        // Before anything else, so the log has a start marker to anchor to and the
        // previous run's ending is on record while it can still be attributed.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let crashed = PersistentLog.shared.startSession(version: version, pid: ProcessInfo.processInfo.processIdentifier)

        self.walkingPadService = WalkingPadService()
        self.bluetoothDiscoverService = BluetoothDiscoveryService(walkingPadService)
        self.mqttService = MqttService(FileSystem())
        super.init()

        // Polling timer: requests a status update from the treadmill and checks for date rollover.
        self.updateTimer = RepeatingTimer(interval: 5, eventHandler: {
            self.workout.resetIfDateChanged()
            self.stravaService.resetIfDateChanged()
            self.walkingPadService.command()?.updateStatus()
        })

        // Slow treadmill when duration limit is hit
        workout.onSpeedNudge = { [weak self] speed in
            self?.walkingPadService.command()?.setSpeed(speed: speed)
        }

        workout.onSessionStateChange = { [weak self] in
            self?.updateStatusBarTitle()
        }

        // Push completed sessions to Notion, then fetch today's total for status bar
        workout.onSessionComplete = { [weak self] session, sessionNumber in
            guard let self = self, self.notionService.isConfigured else { return }
            Task {
                let success = await self.notionService.pushSession(session, sessionNumber: sessionNumber)
                if success {
                    appLog("Notion push succeeded, clearing local workout data")
                    if let emptyData = try? JSONEncoder().encode(WorkoutsSaveData(workouts: [])) {
                        FileSystem().save(filename: "workouts.json", data: emptyData)
                    }

                    // Fetch today's total from Notion for the status bar
                    if let sessions = await self.notionService.fetchTodaySessions() {
                        let totalDist = sessions.reduce(0) { $0 + $1.distance }
                        await MainActor.run {
                            self.workout.todayTotalDistance = totalDist
                        }
                    }

                    // Update widget with full Notion data
                    if let allSessions = await self.notionService.fetchAllSessions() {
                        let workouts = NotionService.groupSessionsByDate(allSessions)
                        await MainActor.run {
                            self.workout.updateWidgetData(from: workouts)
                        }
                    }
                }
            }
        }

        // Central callback chain: every BLE status notification flows through here
        // to update the workout accumulator and publish MQTT state
        self.walkingPadService.callback = { oldState, newState in
            self.workout.update(oldState, newState)
            self.mqttService.publish(oldState: oldState, newState: newState, workoutState: self.workout.workoutState())
            // Update status bar after @Published mutations have been dispatched
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    self.updateStatusBarTitle()
                }
            }
        }

        // onSessionComplete is set above, so a session recovered from a crash
        // checkpoint during Workout.init() can now be pushed on to Notion.
        if crashed {
            appLog("Previous run ended unexpectedly — see \(PersistentLog.shared.currentFile.path)", type: .error)
        }
        self.workout.flushRecoveredSession()

        self.mqttService.start()
        self.updateTimer?.start();
        self.bluetoothDiscoverService.start()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receiveSleepNotification), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receiveWakeNotification), name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Pauses all background services when the Mac goes to sleep.
    @objc func receiveSleepNotification(sender: AnyObject){
        appLog("Received sleep notification, stopping timer");
        self.updateTimer?.stop();
        self.mqttService.stop()
    }

    /// Restarts all services after waking from sleep.
    /// Attempts to reconnect to the previously-known BLE peripheral after a 2-second delay
    /// to give CoreBluetooth time to reinitialize.
    @objc func receiveWakeNotification(sender: AnyObject) {
        appLog("Received wake notification, reinitializing services");

        self.updateTimer?.stop()
        self.mqttService.stop()

        self.bluetoothDiscoverService.start()
        self.mqttService.start()
        self.updateTimer?.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.bluetoothDiscoverService.reconnectToKnownPeripheral()
        }

        self.workout.resetIfDateChanged()
        self.stravaService.resetIfDateChanged()

        // Re-check if yesterday's sessions need syncing (relevant after overnight sleep)
        Task {
            if self.notionService.isConfigured {
                await self.stravaService.checkYesterdaySync(notionService: self.notionService)
            }
        }
    }

    /// Records that this run ended on purpose. Without it every quit looks identical
    /// to a crash on the next launch, and the crash marker stops meaning anything.
    func applicationWillTerminate(_ notification: Notification) {
        workout.save()
        PersistentLog.shared.finishSession(reason: "user quit")
    }

    /// Sets up the status bar menu item, starts the HTTP API server, and fetches today's stats.
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Start Sparkle auto-updater
        AppDelegate.updaterController.startUpdater()

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            appLog("Notification permission \(granted ? "granted" : "denied")")
        }

        // HTTP server runs on a background thread (blocks with loop.runForever())
        DispatchQueue.global(qos: .userInitiated).async {
            startHttpServer(walkingPadService: self.walkingPadService, workout: self.workout)
        }

        // The popover is a system NSPopover, so it gets the standard Liquid Glass
        // background and follows the system's glass and light/dark settings.
        // Width is fixed by ContentView; preferredContentSize lets the height
        // follow the content, which differs per state.
        let hostingController = NSHostingController(rootView: ContentView()
                                    .environmentObject(workout)
                                    .environmentObject(walkingPadService)
                                    .environmentObject(GoalSettings.shared))
        hostingController.sizingOptions = [.preferredContentSize]

        self.popover = NSPopover()
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        self.contextMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit WalkingPad", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)

        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        if let button = self.statusBarItem.button {
            button.imagePosition = .imageLeading
            // Monospaced digits keep the item width stable while the timer ticks
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusBarTitle()

        // Every second: advance session timing (so a quiet treadmill still pauses
        // and ends a session) and refresh the title so the timer ticks live.
        let statusBarTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.workout.tick()
            self.updateStatusBarTitle()
        }
        RunLoop.main.add(statusBarTimer, forMode: .common)

        // Redraw when the goal changes.
        goalObserver = GoalSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusBarTitle() }
        }

        // Fetch today's total from Notion for the status bar on launch,
        // and check if yesterday's sessions need syncing to Strava
        Task {
            if self.notionService.isConfigured {
                if let sessions = await self.notionService.fetchTodaySessions() {
                    let totalDist = sessions.reduce(0) { $0 + $1.distance }
                    await MainActor.run {
                        self.workout.todayTotalDistance = totalDist
                        self.updateStatusBarTitle()
                    }
                }
                await self.stravaService.checkYesterdaySync(notionService: self.notionService)

                // Fetch all sessions from Notion to populate the widget with the last 7 days
                if let allSessions = await self.notionService.fetchAllSessions() {
                    let workouts = NotionService.groupSessionsByDate(allSessions)
                    await MainActor.run {
                        self.workout.updateWidgetData(from: workouts)
                    }
                }
            } else {
                // No Notion configured — use local data
                await MainActor.run {
                    self.workout.updateWidgetData()
                }
            }
        }
    }

    @objc func update() {
        self.walkingPadService.command()?.updateStatus()
    }

    @objc private func quitFromMenu() {
        AppDelegate.quit(walkingPadService: walkingPadService, workout: workout)
    }

    /// Stops the belt, saves, and quits. Shared by the right-click menu and the popover.
    static func quit(walkingPadService: WalkingPadService, workout: Workout) {
        walkingPadService.command()?.setSpeed(speed: 0)
        workout.save()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Popover

    /// Left click toggles the popover; right click (or control-click) shows Quit.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isContextClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isContextClick {
            popover.performClose(nil)
            statusBarItem.menu = contextMenu
            sender.performClick(nil)
            statusBarItem.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Whether a just-ended session was on screen while the popover was open.
    private var recentSessionWasShown = false

    func popoverWillShow(_ notification: Notification) {
        recentSessionWasShown = workout.recentSession != nil
    }

    func popoverDidClose(_ notification: Notification) {
        // "Session saved" stays until it has been seen once.
        if recentSessionWasShown {
            workout.dismissRecentSession()
        }
        recentSessionWasShown = false
    }

    // MARK: - Status bar

    /// Redraws the menu bar item: a goal ring plus one piece of text.
    /// - Walking: session timer
    /// - Just finished a session: "+0.42 km" for a few seconds
    /// - Otherwise: today's total
    private func updateStatusBarTitle() {
        guard let button = self.statusBarItem?.button else { return }

        let goal = GoalSettings.shared
        let progress = goal.progress(distanceMeters: workout.todayDistance, steps: workout.steps, seconds: workout.walkingSeconds)
        let connected = walkingPadService.isConnected()

        let style: StatusBarIcon.Style
        let title: String

        if let sessionStart = workout.currentSessionStartTime {
            style = .walking
            let elapsed = Int(Date().timeIntervalSince(sessionStart))
            let hours = elapsed / 3600
            let mins = (elapsed % 3600) / 60
            let secs = elapsed % 60
            title = hours > 0
                ? String(format: "%d:%02d:%02d", hours, mins, secs)
                : String(format: "%d:%02d", mins, secs)
        } else {
            style = !connected ? .disconnected : (progress >= 1 ? .goalReached : .progress)
            if let recent = workout.recentSession,
               let endedAt = workout.recentSessionEndedAt,
               Date().timeIntervalSince(endedAt) < 5 {
                title = "+" + Self.shortDistance(recent.distance)
            } else {
                let total = workout.todayDistance
                title = total > 0 ? Self.shortDistance(total) : ""
            }
        }

        let image = StatusBarIcon.image(style: style, progress: progress)
        if button.image !== image { button.image = image }
        let spaced = title.isEmpty ? "" : " " + title
        if button.title != spaced { button.title = spaced }
    }

    /// "2.7 km" / "640 m" — one decimal keeps the menu bar item narrow.
    static func shortDistance(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000.0) : "\(meters) m"
    }
}
