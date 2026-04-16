import Foundation

/// A single day's walking distance for the widget display.
struct DailyDistance: Codable {
    let dateString: String   // "2026-04-15"
    let distance: Int        // meters
    let steps: Int
}

/// Snapshot of weekly walking data shared between the main app and the widget extension
/// via a JSON file in the Autosave Information directory.
struct WidgetData: Codable {
    /// Last 7 days of distances, sorted oldest to newest (index 0 = 6 days ago, index 6 = today).
    let weeklyDistances: [DailyDistance]
    /// Sum of all distances in `weeklyDistances`, in meters.
    let totalDistanceMeters: Int
    let lastUpdated: Date

    private static let filename = "widgetData.json"

    /// Directory used by both the main app and the widget extension.
    private static var sharedDirectory: URL {
        let paths = FileManager.default.urls(for: .autosavedInformationDirectory, in: .userDomainMask)
        let dir = paths[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Reads widget data from the shared JSON file.
    static func read() -> WidgetData? {
        let url = sharedDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    /// Writes widget data to the shared JSON file.
    func write() {
        let url = Self.sharedDirectory.appendingPathComponent(Self.filename)
        guard let encoded = try? JSONEncoder().encode(self) else { return }
        try? encoded.write(to: url)
    }
}
