import WidgetKit
import SwiftUI

struct WalkingPadEntry: TimelineEntry {
    let date: Date
    let totalDistanceKm: Double
}

struct WalkingPadWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WalkingPadEntry {
        WalkingPadEntry(date: Date(), totalDistanceKm: 5.0)
    }

    func getSnapshot(in context: Context, completion: @escaping (WalkingPadEntry) -> ()) {
        completion(WalkingPadEntry(date: Date(), totalDistanceKm: 5.0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WalkingPadEntry>) -> ()) {
        let entry = WalkingPadEntry(date: Date(), totalDistanceKm: 0)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

@main
struct WalkingPadWidget: Widget {
    let kind: String = "WalkingPadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WalkingPadWidgetProvider()) { entry in
            Text("\(entry.totalDistanceKm, specifier: "%.1f") km")
        }
        .configurationDisplayName("Walking Distance")
        .description("Weekly walking distance from your WalkingPad.")
        .supportedFamilies([.systemMedium])
    }
}
