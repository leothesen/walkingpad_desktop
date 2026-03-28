import Foundation

/// Represents a delta between two consecutive treadmill state updates.
/// Used by StepsUploader to detect treadmill stop events (oldSpeed > 0, newSpeed == 0)
/// and accumulate steps for batch upload.
public struct Change {
    var oldTime: Date
    var newTime: Date
    /// Number of new steps since the last update
    var stepsDiff: Int
    /// Previous speed in tenths of km/h
    var oldSpeed: Int
    /// Current speed in tenths of km/h
    var newSpeed: Int
}
