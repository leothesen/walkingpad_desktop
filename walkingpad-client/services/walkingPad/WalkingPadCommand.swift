import Foundation
import CoreBluetooth

/// Builds and writes BLE commands to the WalkingPad's FE02 characteristic.
///
/// Command format: `[0xF7, 0xA2, <cmd>, <param>, <checksum>, 0xFD]`
/// - 0xF7 (247): start byte
/// - 0xA2 (162): command type marker
/// - checksum: sum of bytes between start and checksum positions (UInt8 wrapping overflow)
/// - 0xFD (253): end byte
///
/// The checksum placeholder (0xFF) is replaced by `fixChecksum()` before writing.
public class WalkingPadCommand {
    private var connection: WalkingPadConnection
    private var pendingSpeedWorkItem: DispatchWorkItem?

    init(_ connection: WalkingPadConnection) {
        self.connection = connection
    }

    /// Computes the checksum for a command byte array.
    /// Sums all bytes between the first byte (start marker) and the last two bytes
    /// (checksum + end marker), using UInt8 wrapping addition to handle overflow.
    private func fixChecksum(values: [UInt8]) -> [UInt8] {
        let elements: [UInt8] = values.dropFirst().dropLast(2)
        let checksum: UInt8 = elements.reduce(0, {a, b in a.addingReportingOverflow(UInt8(b)).partialValue});
        var copy = Array(values)
        copy[copy.endIndex - 2] = checksum
        return copy
    }

    /// Writes a command to the FE02 characteristic (write without response).
    public func executeCommand(command: [UInt8]) {
        let withChecksum = self.fixChecksum(values: command)
        let data = Data(withChecksum)

        let characteristic = self.connection.commandCharacteristic
        self.connection.peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    /// Sets the treadmill speed. Value is in tenths of km/h (e.g., 25 = 2.5 km/h).
    /// Valid range: 0 (stop) to ~80 (8.0 km/h).
    /// This command is debounced by 150ms to prevent BLE flooding during rapid adjustments.
    public func setSpeed(speed: UInt8) {
        self.pendingSpeedWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.executeCommand(command: [247, 162, 1, speed, 0xff, 253])
            self.pendingSpeedWorkItem = nil
        }
        
        self.pendingSpeedWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    /// Requests the treadmill to send a status notification on FE01.
    /// Called periodically by the RepeatingTimer to keep the UI in sync.
    public func updateStatus() {
        self.executeCommand(command: [247, 162, 0, 0, 162, 253])
    }

    /// Starts the treadmill belt.
    public func start() {
        self.executeCommand(command: [247, 162, 4, 1, 0xff, 253])
    }

    /// Stops the treadmill belt immediately.
    public func stop() {
        // Cancel any pending speed commands before stopping
        self.pendingSpeedWorkItem?.cancel()
        self.pendingSpeedWorkItem = nil
        
        self.executeCommand(command: [247, 162, 4, 2, 0xff, 253])
    }

    /// Sets the treadmill to standby mode.
    public func standby() {
        self.executeCommand(command: [247, 162, 2, 2, 0xff, 253])
    }

    /// Bypasses the mandatory novice guide speed limit.
    /// This tells the treadmill that the initial 1km tutorial is complete.
    public func bypassNoviceGuide() {
        self.executeCommand(command: [247, 162, 10, 1, 0xff, 253])
    }

    /// Wakes the treadmill from standby by setting manual mode, then starts the belt
    /// after a delay to allow the treadmill to initialize.
    /// If already in manual mode, starts immediately.
    public func wakeAndStart(currentState: DeviceState?) {
        if currentState?.walkingMode == .manual {
            appLog("Already in manual mode, starting immediately")
            self.start()
        } else {
            appLog("Not in manual mode (mode=\(String(describing: currentState?.walkingMode))), switching to manual then starting")
            setWalkingMode(mode: .manual)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.start()
            }
        }
    }

    /// Switches between manual and automatic walking modes.
    /// Manual mode allows direct speed control; automatic mode uses the treadmill's built-in program.
    public func setWalkingMode(mode: WalkingMode) {
        let modeVal: UInt8
        switch mode {
        case .automatic: modeVal = 0
        case .manual: modeVal = 1
        case .standby: modeVal = 2
        }
        self.executeCommand(command: [247, 162, 2, modeVal, 0xff, 253])
    }

}
