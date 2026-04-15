import WidgetKit
import SwiftUI

/// Timeline entry containing the weekly walking data snapshot.
struct WalkingPadEntry: TimelineEntry {
    let date: Date
    let widgetData: WidgetData?
}

/// Provides timeline entries by reading from the shared App Group UserDefaults.
struct WalkingPadWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WalkingPadEntry {
        WalkingPadEntry(date: Date(), widgetData: Self.sampleData())
    }

    func getSnapshot(in context: Context, completion: @escaping (WalkingPadEntry) -> ()) {
        let data = context.isPreview ? Self.sampleData() : WidgetData.read()
        completion(WalkingPadEntry(date: Date(), widgetData: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WalkingPadEntry>) -> ()) {
        let data = WidgetData.read()
        let entry = WalkingPadEntry(date: Date(), widgetData: data)
        // Refresh every 30 minutes; the main app writes fresh data to shared UserDefaults on every save.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    /// Sample data used for widget gallery previews and placeholders.
    static func sampleData() -> WidgetData {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sampleDistances = [4200, 5100, 3800, 2600, 0, 0, 0]

        let distances = (0..<7).map { i in
            let date = calendar.date(byAdding: .day, value: -(6 - i), to: today)!
            return DailyDistance(
                dateString: formatter.string(from: date),
                distance: sampleDistances[i],
                steps: sampleDistances[i] * 13 / 10
            )
        }

        return WidgetData(
            weeklyDistances: distances,
            totalDistanceMeters: distances.reduce(0) { $0 + $1.distance },
            lastUpdated: Date()
        )
    }
}

/// The widget configuration.
@main
struct WalkingPadWidget: Widget {
    let kind: String = "WalkingPadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WalkingPadWidgetProvider()) { entry in
            WalkingPadWidgetView(entry: entry)
        }
        .configurationDisplayName("Walking Distance")
        .description("Weekly walking distance from your WalkingPad.")
        .supportedFamilies([.systemMedium])
    }
}
