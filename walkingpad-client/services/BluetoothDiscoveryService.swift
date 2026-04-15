import CoreBluetooth
import Foundation

/// Manages BLE scanning, connection, and reconnection for WalkingPad devices.
///
/// Flow:
/// 1. Uses a CBCentralManager and scans for devices advertising WalkingPad service UUIDs
/// 2. On discovery, wraps the peripheral in BluetoothPeripheral for characteristic discovery
/// 3. If FE01 (notify) and FE02 (command) characteristics are found → confirmed WalkingPad
/// 4. Calls WalkingPadService.onConnect() with the connection details
/// 5. On disconnect, notifies WalkingPadService and attempts to reconnect or restart scanning
///
/// Persistent storage is used to remember the last connected WalkingPad device UUID.
open class BluetoothDiscoveryService: NSObject, CBCentralManagerDelegate, ObservableObject {
    private var centralManager: CBCentralManager!
    /// Devices confirmed as non-WalkingPad during this session. Never persisted or evicted.
    public var peripheralBlacklist: Set<String> = []
    private var walkingPadService: WalkingPadService
    private var bluetoothPeripheral: BluetoothPeripheral? = nil
    private var isStopped: Bool = false
    
    private let lastConnectedDeviceKey = "lastConnectedDeviceUUID"

    init(_ walkingPadService: WalkingPadService) {
        self.walkingPadService = walkingPadService
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    /// Triggers a fresh discovery process.
    /// If already connected, it does not force a disconnect.
    public func start() {
        appLog("Starting Bluetooth discovery")
        self.isStopped = false
        if self.centralManager.state == .poweredOn {
            self.reconnectOrScan()
        }
    }

    /// Internal logic: try to reconnect to a known peripheral, or fall back to scanning.
    private func reconnectOrScan() {
        guard !isStopped else { return }
        
        if self.reconnectToKnownPeripheral() {
            return
        }
        
        appLog("Scanning for devices...")
        self.centralManager.scanForPeripherals(withServices: BluetoothPeripheral.walkingPadServiceUUIDs, options: nil)
    }

    /// Attempts to reconnect to a previously-known peripheral (stored in UserDefaults).
    /// Returns true if a known peripheral was found and a connection attempt was started.
    @discardableResult
    func reconnectToKnownPeripheral() -> Bool {
        guard self.centralManager.state == .poweredOn && !isStopped else { return false }
        
        if let uuidString = UserDefaults.standard.string(forKey: lastConnectedDeviceKey),
           let uuid = UUID(uuidString: uuidString) {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = peripherals.first {
                appLog("Found known peripheral \(peripheral.name ?? "unknown"), connecting...")
                self.bluetoothPeripheral = BluetoothPeripheral(peripheral: peripheral, callback: { bluetoothPeripheral, isWalkingPad in
                    self.handleDiscoveredDevice(bluetoothPeripheral, isWalkingPad)
                })
                centralManager.connect(peripheral, options: nil)
                return true
            }
        }
        
        // Old logic fallback: check if WalkingPadService has a current peripheral that is disconnected
        if let peripheral = walkingPadService.connectedPeripheral(), peripheral.state != .connected {
            appLog("Reconnecting to current peripheral...")
            centralManager.connect(peripheral, options: nil)
            return true
        }
        
        return false
    }

    /// Starts or stops scanning based on Bluetooth power state.
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        appLog("Central Manager State: \(central.state)")
        if (central.state == .poweredOn) {
            self.reconnectOrScan()
        } else {
            self.centralManager.stopScan()
            if central.state != .resetting && central.state != .unknown {
                self.walkingPadService.onDisconnect()
            }
        }
    }

    /// Called for each discovered peripheral. Skips blacklisted devices and connects to
    /// the first unknown device to check if it's a WalkingPad (one device at a time).
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard !isStopped else { return }
        if (!self.peripheralBlacklist.contains(peripheral.identifier.uuidString)
            && self.bluetoothPeripheral == nil
        ) {
            appLog("Discovered potential device: \(peripheral.name ?? "unknown")")
            self.bluetoothPeripheral = BluetoothPeripheral(peripheral: peripheral, callback: { bluetoothPeripheral, isWalkingPad in
                self.handleDiscoveredDevice(bluetoothPeripheral, isWalkingPad)

            })
            self.centralManager.connect(peripheral, options: nil)
        }
    }

    /// Once connected, begin service/characteristic discovery to identify the device.
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appLog("Connected to \(peripheral.name ?? "unknown"), discovering services...")
        self.bluetoothPeripheral?.discover()
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        appLog("Failed to connect to \(peripheral.name ?? "unknown"): \(error?.localizedDescription ?? "unknown error")", type: .error)
        if self.bluetoothPeripheral?.peripheral == peripheral {
            self.bluetoothPeripheral = nil
        }
        // Fall back to scanning
        self.reconnectOrScan()
    }

    /// Routes the device identification result: connect to WalkingPad or blacklist + disconnect.
    private func handleDiscoveredDevice(_ peripheral: BluetoothPeripheral, _ isWalkingPad: Bool) {
        if (isWalkingPad) {
            appLog("Confirmed WalkingPad: \(peripheral.peripheral.name ?? "unknown")")
            UserDefaults.standard.set(peripheral.peripheral.identifier.uuidString, forKey: lastConnectedDeviceKey)
            
            self.walkingPadService.onConnect(WalkingPadConnection(
                peripheral: peripheral.peripheral,
                notifyCharacteristic: peripheral.notifyCharacteristic!,
                commandCharacteristic: peripheral.commandCharacteristic!
            ))
            self.centralManager.stopScan()
            self.bluetoothPeripheral = nil
        } else {
            appLog("Device is not a WalkingPad, blacklisting: \(peripheral.peripheral.name ?? "unknown")")
            self.peripheralBlacklist.insert(peripheral.peripheral.identifier.uuidString)
            self.centralManager?.cancelPeripheralConnection(peripheral.peripheral)
            self.bluetoothPeripheral = nil
            // Resume scanning if we are still looking
            self.reconnectOrScan()
        }
    }

    public func stop() {
        appLog("Stopping Bluetooth discovery and disconnecting")
        self.isStopped = true
        self.centralManager.stopScan()
        self.bluetoothPeripheral = nil
        if let peripheral = walkingPadService.connectedPeripheral() {
            self.centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    /// Auto-restarts scanning when a device disconnects.
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        appLog("Device \(peripheral.name ?? "unknown") disconnected: \(error?.localizedDescription ?? "no error")")
        
        if (self.walkingPadService.isCurrentDevice(peripheral: peripheral)) {
            self.walkingPadService.onDisconnect()
            
            // Wait a bit before attempting to reconnect to avoid rapid cycling
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.reconnectOrScan()
            }
        } else if self.bluetoothPeripheral?.peripheral == peripheral {
            self.bluetoothPeripheral = nil
            self.reconnectOrScan()
        }
    }
}
