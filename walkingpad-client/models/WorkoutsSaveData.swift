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

/// The walking session currently in progress, mirrored to disk.
///
/// `Workout` only appends to `todaySessions` when a session *ends*, while the daily
/// totals are accumulated on every BLE update. That asymmetry means an app death
/// mid-walk keeps the distance in the day's total but loses the session itself — and
/// since Notion and Strava are both fed from sessions, the walk silently never
/// arrives anywhere. On 2026-09-07 that cost a 2.62 km session.
///
/// So the in-flight session is written here on every update and removed when one ends
/// cleanly. A checkpoint still present at launch therefore means exactly one thing:
/// the last session never finished, and its distance is owed to `todaySessions`.
struct SessionCheckpoint: Codable {
    var startTime: Date
    /// Time of the last BLE update folded into this session — the best available
    /// estimate of when the walking actually stopped.
    var lastUpdate: Date
    var steps: Int
    /// Distance in meters
    var distance: Int

    static let filename = "session-checkpoint.json"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        FileSystem().save(filename: SessionCheckpoint.filename, data: data)
    }

    static func load() -> SessionCheckpoint? {
        guard let data = FileSystem().load(filename: filename) else { return nil }
        return try? JSONDecoder().decode(SessionCheckpoint.self, from: data)
    }

    static func clear() {
        FileSystem().remove(filename: filename)
    }
}
