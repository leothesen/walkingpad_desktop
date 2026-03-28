import Foundation

/// A single day's workout record, persisted to workouts.json.
struct WorkoutSaveData: Codable {
    var steps: Int
    /// Distance in meters
    var distance: Int
    var walkingSeconds: Int
    var date: Date
}

/// Top-level wrapper for the workouts.json persistence file.
/// Contains an array of daily workout records (max 500, older entries are silently dropped).
struct WorkoutsSaveData: Codable {
    var workouts: [WorkoutSaveData]
}
