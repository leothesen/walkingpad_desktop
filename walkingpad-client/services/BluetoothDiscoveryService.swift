import CoreBluetooth
import Foundation

/// Manages BLE scanning, connection, and reconnection for WalkingPad devices.
///
/// Flow:
/// 1. Creates a CBCentralManager and scans for devices advertising WalkingPad service UUIDs
/// 2. On discovery, wraps the peripheral in BluetoothPeripheral for characteristic discovery
/// 3. If FE01 (notify) and FE02 (command) characteristics are found → confirmed WalkingPad
/// 4. Calls WalkingPadService.onConnect() with the connection details
/// 5. On disconnect, notifies WalkingPadService and restarts scanning
///
/// Non-WalkingPad devices are added to an in-memory blacklist to avoid repeated connection attempts.
open class BluetoothDiscoveryService: NSObject, CBCentralManagerDelegate, ObservableObject {
    private var centralManager: CBCentralManager! = nil
    /// Devices confirmed as non-WalkingPad during this session. Never persisted or evicted.
    public var peripheralBlacklist: Set<String> = []
    private var walkingPadService: WalkingPadService
    private var bluetoothPeripheral: BluetoothPeripheral? = nil

    init(_ walkingPadService: WalkingPadService) {
        self.walkingPadService = walkingPadService
    }

    /// (Re)initializes the CBCentralManager and begins scanning.
    /// Also called on disconnect to restart the discovery process.
    public func start() {
        self.centralManager = nil
        self.bluetoothPeripheral = nil
        self.walkingPadService.onDisconnect()

        // queue: nil means callbacks arrive on the main thread
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        print("Central Manager State: \(self.centralManager.state)")

        // Kick off scanning after a short delay to handle cases where BT is already powered on
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.centralManagerDidUpdateState(self.centralManager)
        }
    }

    /// Attempts to reconnect to a previously-known peripheral (used after wake from sleep).
    func reconnectToKnownPeripheral() {
        guard let peripheral = walkingPadService.connectedPeripheral() else { return }
        if centralManager.state == .poweredOn && peripheral.state != .connected {
            centralManager.connect(peripheral, options: nil)
        }
    }

    /// Starts or stops scanning based on Bluetooth power state.
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if (central.state == .poweredOn) {
            print("Scanning for devices");
            self.centralManager.scanForPeripherals(withServices: BluetoothPeripheral.walkingPadServiceUUIDs, options: nil)
        } else {
            self.centralManager.stopScan()
        }
    }

    /// Called for each discovered peripheral. Skips blacklisted devices and connects to
    /// the first unknown device to check if it's a WalkingPad (one device at a time).
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if (!self.peripheralBlacklist.contains(peripheral.identifier.uuidString)
            && self.bluetoothPeripheral == nil
        ) {
            self.bluetoothPeripheral = BluetoothPeripheral(peripheral: peripheral, callback: { bluetoothPeripheral, isWalkingPad in
                self.handleDiscoveredDevice(bluetoothPeripheral, isWalkingPad)

            })
            self.centralManager.connect(peripheral, options: nil)
        }
    }

    /// Once connected, begin service/characteristic discovery to identify the device.
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.bluetoothPeripheral?.discover()
    }

    /// Routes the device identification result: connect to WalkingPad or blacklist + disconnect.
    private func handleDiscoveredDevice(_ peripheral: BluetoothPeripheral, _ isWalkingPad: Bool) {
        if (isWalkingPad) {
            self.walkingPadService.onConnect(WalkingPadConnection(
                peripheral: peripheral.peripheral,
                notifyCharacteristic: peripheral.notifyCharacteristic!,
                commandCharacteristic: peripheral.commandCharacteristic!
            ))
            self.centralManager.stopScan()
            self.bluetoothPeripheral = nil
        } else {
            self.peripheralBlacklist.insert(peripheral.peripheral.identifier.uuidString)
            self.centralManager?.cancelPeripheralConnection(peripheral.peripheral)
            self.bluetoothPeripheral = nil
        }
    }

    public func stop() {
        self.centralManager.stopScan()
        self.bluetoothPeripheral = nil
    }

    /// Auto-restarts scanning when a device disconnects.
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Device is disconnected, starting scan again.")
        if (self.walkingPadService.isCurrentDevice(peripheral: peripheral)) {
            self.walkingPadService.onDisconnect()
        }
        self.start()
    }
}
