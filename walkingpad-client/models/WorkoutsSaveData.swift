import Foundation

/// A single walking session within a day (start → stop transition).
struct SessionSaveData: Codable {
    var startTime: Date
    var endTime: Date
    var steps: Int
    /// Distance in meters
    var distance: Int
}

/// A single day's workout record, persisted to workouts.json.
struct WorkoutSaveData: Codable {
    var steps: Int
    /// Distance in meters
    var distance: Int
    var walkingSeconds: Int
    var date: Date
    /// Individual sessions recorded during this day. Optional for backwards compatibility —
    /// old entries without this field decode as nil.
    var sessions: [SessionSaveData]?
}

/// Top-level wrapper for the workouts.json persistence file.
/// Contains an array of daily workout records (max 500, older entries are silently dropped).
struct WorkoutsSaveData: Codable {
    var workouts: [WorkoutSaveData]
}
