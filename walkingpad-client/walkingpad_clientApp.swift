import SwiftUI

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
/// - Creates and connects all services (BLE, MQTT, HTTP API, health sync)
/// - Sets up the callback chain: BLE → Workout → StepsUploader / MQTT
/// - Manages the status bar item and popover UI
/// - Handles sleep/wake notifications to pause and resume services
class AppDelegate: NSObject, NSApplicationDelegate {
    private var workout = Workout()
    private var walkingPadService: WalkingPadService
    private var bluetoothDiscoverService: BluetoothDiscoveryService
    private var stepsUploader: StepsUploader
    private var updateTimer: RepeatingTimer? = nil;
    private var mqttService: MqttService
    private var hcGatewayService: HCGatewayService

    var popover: NSPopover!
    var statusBarItem: NSStatusItem!

    override init() {
        self.walkingPadService = WalkingPadService()
        self.bluetoothDiscoverService = BluetoothDiscoveryService(walkingPadService)
        self.mqttService = MqttService(FileSystem())

        self.hcGatewayService = HCGatewayService()
        self.stepsUploader = StepsUploader(hcGatewayService: self.hcGatewayService)

        super.init()

        // Polling timer: requests a status update from the treadmill and checks for date rollover.
        // Note: the interval parameter is currently ignored by RepeatingTimer (hardcodes 4s).
        self.updateTimer = RepeatingTimer(interval: 5, eventHandler: {
            self.workout.resetIfDateChanged()
            self.walkingPadService.command()?.updateStatus()
        })

        // Step upload callback: dispatched to a background queue to avoid blocking BLE callbacks
        workout.onChangeCallback = {
            change in DispatchQueue.global(qos: .userInitiated).async {
                self.stepsUploader.handleChange(change)
            }
        }

        // Central callback chain: every BLE status notification flows through here
        // to update the workout accumulator and publish MQTT state
        self.walkingPadService.callback = { oldState, newState in
            self.workout.update(oldState, newState)
            self.mqttService.publish(oldState: oldState, newState: newState, workoutState: self.workout.workoutState())
        }

        self.mqttService.start()
        self.updateTimer?.start();
        self.bluetoothDiscoverService.start()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receiveSleepNotification), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receiveWakeNotification), name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Pauses all background services when the Mac goes to sleep.
    @objc func receiveSleepNotification(sender: AnyObject){
        NSLog("Received sleep notification, stopping timer");
        self.updateTimer?.stop();
        self.mqttService.stop()
        self.stepsUploader.reset()
    }

    /// Restarts all services after waking from sleep.
    /// Attempts to reconnect to the previously-known BLE peripheral after a 2-second delay
    /// to give CoreBluetooth time to reinitialize.
    @objc func receiveWakeNotification(sender: AnyObject) {
        NSLog("Received wake notification, reinitializing services");

        self.updateTimer?.stop()
        self.mqttService.stop()

        self.bluetoothDiscoverService.start()
        self.mqttService.start()
        self.updateTimer?.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.bluetoothDiscoverService.reconnectToKnownPeripheral()
        }

        self.stepsUploader.reset()
        self.workout.resetIfDateChanged()
    }

    /// Sets up the status bar menu item, starts the HTTP API server, and initializes HCGateway auth.
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // HTTP server runs on a background thread (blocks with loop.runForever())
        DispatchQueue.global(qos: .userInitiated).async {
            startHttpServer(walkingPadService: self.walkingPadService, workout: self.workout)
        }

        // Create the SwiftUI popover hosted inside an NSMenu attached to the status bar icon
        let view = NSHostingView(rootView: ContentView()
                                    .environmentObject(workout)
                                    .environmentObject(walkingPadService)
                                    .environmentObject(hcGatewayService))
        let menuItem = NSMenuItem()
        menuItem.view = view
        view.frame = NSRect(x: 0, y: 0, width: 220, height: 310)

        let menu = NSMenu()
        menu.addItem(menuItem)

        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        self.statusBarItem.menu = menu
        if let button = self.statusBarItem.button {
            button.image = NSImage(named: "StatusIcon")
            button.image?.isTemplate = true
        }

        // Refresh or validate the HCGateway access token on launch
        Task {
            await self.hcGatewayService.initialize()
        }
    }

    @objc func update() {
        self.walkingPadService.command()?.updateStatus()
    }
}
