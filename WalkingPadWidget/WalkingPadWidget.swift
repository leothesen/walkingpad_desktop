import WidgetKit
import SwiftUI

/// Timeline entry containing the walking data snapshot.
struct WalkingPadEntry: TimelineEntry {
    let date: Date
    let widgetData: WidgetData?
}

/// Provides timeline entries from the JSON file the main app writes into the widget's container.
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
        let now = Date()
        var entries = [WalkingPadEntry(date: now, widgetData: data)]
        // Move the grid on to a new day at midnight, even if the app hasn't written since.
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
            entries.append(WalkingPadEntry(date: midnight, widgetData: data))
        }
        // The app reloads the widget whenever it writes new data; this is a fallback.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now)!
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    /// Sample data used for widget gallery previews and placeholders.
    static func sampleData() -> WidgetData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Fixed pattern so the gallery preview looks the same every time.
        let pattern = [6.2, 7.9, 0, 8.4, 5.1, 0, 0, 4.4, 9.0, 6.7, 0, 3.2, 2.1, 0, 7.5, 8.8, 5.6, 8.1, 4.0, 0, 0]
        let days = (0..<63).map { offset -> WidgetDay in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let km = offset == 0 ? 3.4 : pattern[offset % pattern.count]
            return WidgetDay(
                dateString: WidgetData.dateString(date),
                distance: Int(km * 1000),
                steps: Int(km * 1300),
                seconds: Int(km * 900)
            )
        }.reversed()

        return WidgetData(
            days: Array(days),
            goal: WidgetGoal(kind: .distance, value: 8),
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
        .configurationDisplayName("Walking")
        .description("Today's progress toward your goal, and every day of the last two months.")
        .supportedFamilies([.systemMedium])
    }
}
