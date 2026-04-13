import Foundation
import CoreBluetooth

/// Callback type for treadmill state changes. `oldState` is nil on the first update after connection.
public typealias TreadmillCallback = (_ oldState: DeviceState?, _ newState: DeviceState) -> Void

/// Holds the active BLE connection's peripheral and the two characteristics used for communication.
public struct WalkingPadConnection {
    var peripheral: CBPeripheral
    /// FE01 — receives status notifications from the treadmill
    var notifyCharacteristic: CBCharacteristic
    /// FE02 — accepts commands (speed, start, mode) written to the treadmill
    var commandCharacteristic: CBCharacteristic
}

/// Central service for WalkingPad BLE communication.
///
/// Responsibilities:
/// - Receives and parses binary status notifications from the FE01 characteristic
/// - Maintains the latest `DeviceState` and publishes changes via `callback`
/// - Provides a `WalkingPadCommand` factory for writing commands to FE02
///
/// Status notification byte layout (14+ bytes):
/// ```
/// [0-1] Status type: 0xF8 0xA2 = current, 0xF8 0xA7 = last session
/// [2]   Reserved
/// [3]   Speed (raw, divide by 10 for km/h)
/// [4]   Walking mode (1 = manual, 0 = automatic)
/// [5-7] Walking time in seconds (big-endian)
/// [8-10] Distance (big-endian, multiply by 10)
/// [11-13] Steps (big-endian)
/// ```
/// A single timestamped BLE log entry for the debug console.
public struct BLELogEntry: Identifiable {
    public let id = UUID()
    public let time: Date
    public let message: String
}

open class WalkingPadService: NSObject, CBPeripheralDelegate, ObservableObject {

    private var connection: WalkingPadConnection?
    @Published
    private var lastState: DeviceState? = nil

    /// Rolling buffer of recent BLE events for the debug console (max 200).
    @Published
    public var debugLog: [BLELogEntry] = []
    private let maxLogEntries = 200

    public var callback: TreadmillCallback?

    private func log(_ message: String) {
        let entry = BLELogEntry(time: Date(), message: message)
        DispatchQueue.main.async {
            self.debugLog.append(entry)
            if self.debugLog.count > self.maxLogEntries {
                self.debugLog.removeFirst(self.debugLog.count - self.maxLogEntries)
            }
        }
    }

    /// Called by BluetoothDiscoveryService when a WalkingPad device is identified and connected.
    /// Subscribes to FE01 notifications to start receiving status updates.
    public func onConnect(_ connection: WalkingPadConnection) {
        self.connection = connection
        self.connection?.peripheral.delegate = self
        connection.peripheral.setNotifyValue(true, for: connection.notifyCharacteristic)
        let name = connection.peripheral.name ?? "unknown"
        appLog("Initialized walking pad connection to \(name)")
        log("Connected to \(name)")
    }

    /// Called on BLE disconnect. Fires a zero-speed callback to trigger upload/save
    /// logic that depends on the treadmill stopping, then clears state.
    public func onDisconnect() {
        appLog("WalkingPad device disconnected, setting state to nil")
        log("Disconnected")
        self.notifyZeroSpeed()
        DispatchQueue.main.async {
            self.lastState = nil
        }
    }

    /// Synthesizes a zero-speed state from the last known state and fires the callback.
    /// This ensures the StepsUploader detects a "treadmill stopped" transition on disconnect.
    private func notifyZeroSpeed() {
        guard let state = self.lastState else { return }
        appLog("Notifying with zero speed.")
        self.callback?(state, DeviceState(
            time: Date(),
            walkingTimeSeconds: state.walkingTimeSeconds,
            speed: 0,
            steps: state.steps,
            distance: state.distance,
            walkingMode: state.walkingMode,
            deviceName: state.deviceName,
            statusType: state.statusType
        ))
    }

    public func isCurrentDevice(peripheral: CBPeripheral) -> Bool {
        return peripheral == self.connection?.peripheral
    }

    public func connectedPeripheral() -> CBPeripheral? {
        return self.connection?.peripheral
    }

    /// Returns a command object for writing to the treadmill, or nil if not connected.
    public func command() -> WalkingPadCommand? {
        guard let connection = self.connection else { return nil }
        return WalkingPadCommand(connection)
    }

    /// Decodes a big-endian multi-byte integer from an array of UInt8 values.
    /// For example, [0x01, 0x02, 0x03] → 1*65536 + 2*256 + 3 = 66051.
    private func sumFrom(_ values: [UInt8]) -> Int {
        return values.reduce(0, { acc, value in acc * 256 + Int(value) })
    }

    /// Identifies the status type from the first two bytes of a notification.
    /// - 0xF8 0xA2 (248, 162) → current real-time status
    /// - 0xF8 0xA7 (248, 167) → last session summary
    private func statusTypeFrom(_ bits: [UInt8]) -> StatusType? {
        if (bits[0] == 248 && bits[1] == 162) {
            return .currentStatus
        }
        if (bits[0] == 248 && bits[1] == 167) {
            return .lastStatus
        }
        return nil
    }

    /// CoreBluetooth delegate: called when the FE01 characteristic sends a notification.
    /// Parses the binary payload into a DeviceState and fires the callback chain.
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value {

            let byteArray = [UInt8](value)

            let hexString = byteArray.map { String(format: "%02x", $0) }.joined(separator: " ")
            log("RX [\(byteArray.count)B] \(hexString)")

            guard let statusType = statusTypeFrom(Array(byteArray[0...2])) else { return }
            guard let connection = self.connection else { return }

            // Need at least 14 bytes to read steps at index 11-13
            if (byteArray.count < 13) {
                log("⚠ Short payload: \(byteArray.count) bytes")
                appLog("Unknown status array length")
                return
            }

            let speed = byteArray[3]
            let isManualMode = byteArray[4] == 1
            let distance = sumFrom(Array(byteArray[8...10])) * 10
            let steps = sumFrom(Array(byteArray[11...13]))
            let walkingTimeSeconds = sumFrom(Array(byteArray[5...7]))

            let type = statusType == .currentStatus ? "curr" : "last"
            log("\(type) spd=\(speed) steps=\(steps) dist=\(distance) time=\(walkingTimeSeconds)s mode=\(isManualMode ? "M" : "A")")

            let status = DeviceState(
                time: Date(),
                walkingTimeSeconds: walkingTimeSeconds,
                speed: Int(speed),
                steps: Int(steps),
                distance: Int(distance),
                walkingMode: isManualMode ? WalkingMode.manual : WalkingMode.automatic,
                deviceName: connection.peripheral.name ?? "unknown",
                statusType: statusType
            )

            let previousState = self.lastState
            DispatchQueue.main.async {
                self.lastState = status
            }
            self.callback?(previousState, status)
        }
    }

    public func lastStatus() -> DeviceState? {
        return self.lastState
    }

    public func isConnected() -> Bool {
        return self.connection != nil
    }
}
