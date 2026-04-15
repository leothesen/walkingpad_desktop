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
        self.walkingPadService = WalkingPadService()
        self.bluetoothDiscoverService = BluetoothDiscoveryService(walkingPadService)
        self.mqttService = MqttService(FileSystem())
        super.init()

        // Polling timer: requests a status update from the treadmill and checks for date rollover.
        // Note: the interval parameter is currently ignored by RepeatingTimer (hardcodes 4s).
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
                            self.workout.updateWidgetData()
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
                    self.updateStatusBarTitle(speed: newState.speed)
                }
            }
        }

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

        // Create the SwiftUI popover hosted inside an NSMenu attached to the status bar icon
        let view = NSHostingView(rootView: ContentView()
                                    .environmentObject(workout)
                                    .environmentObject(walkingPadService))
        let menuItem = NSMenuItem()
        menuItem.view = view
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 265)

        let menu = NSMenu()
        menu.addItem(menuItem)

        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        self.statusBarItem.menu = menu
        if let button = self.statusBarItem.button {
            button.image = NSImage(named: "StatusIcon")
            button.image?.isTemplate = true
        }

        // Schedule Strava auto-post at 23:59
        scheduleStravaAutoPost()

        // Fetch today's total from Notion for the status bar on launch,
        // and check if yesterday's sessions need syncing to Strava
        Task {
            if self.notionService.isConfigured {
                if let sessions = await self.notionService.fetchTodaySessions() {
                    let totalDist = sessions.reduce(0) { $0 + $1.distance }
                    await MainActor.run {
                        self.workout.todayTotalDistance = totalDist
                        self.updateStatusBarTitle(speed: 0)
                    }
                }
                await self.stravaService.checkYesterdaySync(notionService: self.notionService)
            }
            // Update widget data on launch so the widget has fresh data
            await MainActor.run {
                self.workout.updateWidgetData()
            }
        }
    }

    @objc func update() {
        self.walkingPadService.command()?.updateStatus()
    }

    /// Schedules a Strava auto-post at 23:59 local time.
    private func scheduleStravaAutoPost() {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 23
        components.minute = 59
        guard let fireDate = calendar.date(from: components), fireDate > Date() else {
            appLog("Strava: 23:59 already passed today, skipping auto-post schedule")
            return
        }

        let interval = fireDate.timeIntervalSince(Date())
        appLog("Strava: auto-post scheduled in \(Int(interval / 60)) minutes")
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.autoPostToStrava()
        }
    }

    private func autoPostToStrava() {
        guard stravaService.isConnected, !stravaService.isSyncedToday else {
            appLog("Strava: auto-post skipped (not connected or already synced)")
            scheduleStravaAutoPostForTomorrow()
            return
        }

        Task {
            if let sessions = await notionService.fetchTodaySessions(), !sessions.isEmpty {
                let success = await stravaService.postTodayActivity(sessions: sessions, notionService: notionService)
                appLog("Strava: auto-post \(success ? "succeeded" : "failed")")
            } else {
                appLog("Strava: auto-post skipped (no sessions today)")
            }
            await MainActor.run {
                self.scheduleStravaAutoPostForTomorrow()
            }
        }
    }

    private func scheduleStravaAutoPostForTomorrow() {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else { return }
        var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = 23
        components.minute = 59
        guard let fireDate = calendar.date(from: components) else { return }

        let interval = fireDate.timeIntervalSince(Date())
        appLog("Strava: next auto-post in \(Int(interval / 3600)) hours")
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.autoPostToStrava()
        }
    }

    /// Updates the status bar to show live session stats when walking,
    /// or today's total distance (from Notion) when idle.
    private func updateStatusBarTitle(speed: Int) {
        guard let button = self.statusBarItem?.button else { return }

        if speed > 0, let sessionStart = workout.currentSessionStartTime {
            // Active session: show current session distance + duration
            let dist = workout.sessionDistance
            let elapsed = Int(Date().timeIntervalSince(sessionStart))
            let mins = elapsed / 60
            let secs = elapsed % 60

            let distStr = dist >= 1000 ? String(format: "%.2f km", Double(dist) / 1000.0) : "\(dist) m"
            button.title = " \(distStr) · \(mins):\(String(format: "%02d", secs))"
            button.image = nil
        } else {
            // Idle: show today's total from Notion
            let totalDist = workout.todayTotalDistance
            if totalDist > 0 {
                let distStr = totalDist >= 1000 ? String(format: "%.2f km", Double(totalDist) / 1000.0) : "\(totalDist) m"
                button.title = " \(distStr)"
                button.image = NSImage(named: "StatusIcon")
                button.image?.isTemplate = true
            } else {
                button.title = ""
                button.image = NSImage(named: "StatusIcon")
                button.image?.isTemplate = true
            }
        }
    }
}
