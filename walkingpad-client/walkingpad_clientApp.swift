import SwiftUI
import UserNotifications
import Sparkle

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
class AppDelegate: NSObject, NSApplicationDelegate {
    private var workout = Workout()
    private var walkingPadService: WalkingPadService
    private var bluetoothDiscoverService: BluetoothDiscoveryService
    private var updateTimer: RepeatingTimer? = nil;
    private var mqttService: MqttService
    var notionService: NotionService { NotionService.shared }
    var stravaService: StravaService { StravaService.shared }

    static let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    var popover: NSPopover!
    var statusBarItem: NSStatusItem!

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

        // Create the SwiftUI popover hosted inside an NSMenu attached to the status bar icon.
        // Width is fixed by ContentView; intrinsic sizing lets the menu height follow
        // the content (connected/running/stopped states differ in height) instead of
        // clipping against a hardcoded frame.
        let view = NSHostingView(rootView: ContentView()
                                    .environmentObject(workout)
                                    .environmentObject(walkingPadService))
        view.sizingOptions = [.intrinsicContentSize]
        let menuItem = NSMenuItem()
        menuItem.view = view
        view.frame = NSRect(x: 0, y: 0, width: 230, height: 380)

        let menu = NSMenu()
        menu.addItem(menuItem)

        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        self.statusBarItem.menu = menu
        if let button = self.statusBarItem.button {
            button.image = NSImage(named: "StatusIcon")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            // Monospaced digits keep the item width stable while the timer ticks
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        // Refresh the title every second while a session is active so the
        // duration ticks live instead of jumping on each 5s BLE poll.
        let statusBarTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.workout.currentSessionStartTime != nil else { return }
            self.updateStatusBarTitle()
        }
        RunLoop.main.add(statusBarTimer, forMode: .common)

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

    /// Updates the status bar to show live session stats when walking,
    /// or today's total distance (from Notion) when idle.
    private func updateStatusBarTitle() {
        guard let button = self.statusBarItem?.button else { return }

        // The icon stays visible in all states so the item doesn't change
        // shape when a session starts or the menu is opened.
        if let sessionStart = workout.currentSessionStartTime {
            // Active session: show current session distance + duration
            let dist = workout.sessionDistance
            let elapsed = Int(Date().timeIntervalSince(sessionStart))
            let mins = elapsed / 60
            let secs = elapsed % 60

            let distStr = dist >= 1000 ? String(format: "%.2f km", Double(dist) / 1000.0) : "\(dist) m"
            button.title = " \(distStr) · \(mins):\(String(format: "%02d", secs))"
        } else {
            // Idle: show today's total (Notion total once synced, else local)
            let totalDist = max(workout.todayTotalDistance, workout.distance)
            button.title = totalDist > 0
                ? " " + (totalDist >= 1000 ? String(format: "%.2f km", Double(totalDist) / 1000.0) : "\(totalDist) m")
                : ""
        }
    }
}
