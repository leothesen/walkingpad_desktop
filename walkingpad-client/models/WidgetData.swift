import Foundation

/// A single day's walking distance for the widget display.
struct DailyDistance: Codable {
    let dateString: String   // "2026-04-15"
    let distance: Int        // meters
    let steps: Int
}

/// Snapshot of weekly walking data shared between the main app and the widget extension.
///
/// The main app (non-sandboxed) writes `widgetData.json` into the widget extension's
/// sandbox container. The widget (sandboxed) reads from its own container. No App Groups needed.
struct WidgetData: Codable {
    /// Last 7 days of distances, sorted oldest to newest (index 0 = 6 days ago, index 6 = today).
    let weeklyDistances: [DailyDistance]
    /// Sum of all distances in `weeklyDistances`, in meters.
    let totalDistanceMeters: Int
    let lastUpdated: Date

    private static let filename = "widgetData.json"
    private static let widgetBundleID = "klassm.walkingpad-client.WalkingPadWidget"

    /// Path used by the **main app** to write into the widget's sandbox container.
    /// Works because the main app is non-sandboxed and can write to any path.
    private static var widgetContainerDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Documents")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Path used by the **widget** to read from its own sandbox container.
    private static var sandboxDocumentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Reads widget data from the Documents directory (used by the widget).
    static func read() -> WidgetData? {
        let url = sandboxDocumentsDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    /// Writes widget data into the widget's container (used by the main app).
    func write() {
        let url = Self.widgetContainerDirectory.appendingPathComponent(Self.filename)
        guard let encoded = try? JSONEncoder().encode(self) else { return }
        try? encoded.write(to: url)
    }
}
