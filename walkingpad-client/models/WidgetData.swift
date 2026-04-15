import Foundation

/// A single day's walking distance for the widget display.
struct DailyDistance: Codable {
    let dateString: String   // "2026-04-15"
    let distance: Int        // meters
    let steps: Int
}

/// Snapshot of weekly walking data shared between the main app and the widget extension
/// via App Group UserDefaults.
struct WidgetData: Codable {
    /// Last 7 days of distances, sorted oldest to newest (index 0 = 6 days ago, index 6 = today).
    let weeklyDistances: [DailyDistance]
    /// Sum of all distances in `weeklyDistances`, in meters.
    let totalDistanceMeters: Int
    let lastUpdated: Date

    /// App Group suite name used to share data between the main app and widget.
    static let appGroupID = "group.klassm.walkingpad-client"
    /// UserDefaults key for the encoded widget data.
    static let userDefaultsKey = "widgetData"

    /// Reads widget data from the shared App Group UserDefaults.
    static func read() -> WidgetData? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    /// Writes widget data to the shared App Group UserDefaults.
    func write() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let encoded = try? JSONEncoder().encode(self) else { return }
        defaults.set(encoded, forKey: Self.userDefaultsKey)
    }
}
