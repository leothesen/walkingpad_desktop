import Foundation

/// Treadmill walking mode: manual allows direct speed control,
/// automatic uses the treadmill's built-in speed program.
public enum WalkingMode {
    case manual, automatic
}

/// Distinguishes between real-time status updates and last-session summaries
/// from the BLE notification payload.
public enum StatusType {
    case lastStatus, currentStatus
}

/// Snapshot of the treadmill's state at a point in time, parsed from a BLE notification.
///
/// Speed is stored as a raw integer (tenths of km/h): 25 = 2.5 km/h.
/// Distance is in meters (raw BLE value * 10).
/// Steps and walking time are direct counts from the treadmill.
public struct DeviceState {
    var time: Date
    var walkingTimeSeconds: Int = 0
    /// Speed in tenths of km/h (e.g., 25 = 2.5 km/h)
    var speed: Int = 0
    var steps: Int = 0
    /// Distance in meters
    var distance: Int = 0
    var walkingMode: WalkingMode = WalkingMode.manual
    var deviceName: String
    var statusType: StatusType

    /// Converts the raw speed integer to km/h (e.g., 25 → 2.5).
    func speedKmh() -> Double {
        return Double(speed) / 10
    }
}
