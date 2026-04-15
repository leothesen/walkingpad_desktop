import SwiftUI
import WidgetKit

/// Main widget view: circular distance ring on the left, weekly bar chart on the right.
struct WalkingPadWidgetView: View {
    let entry: WalkingPadEntry

    private var data: WidgetData? { entry.widgetData }

    private var totalKm: Double {
        Double(data?.totalDistanceMeters ?? 0) / 1000.0
    }

    private var distanceText: String {
        if totalKm >= 100 {
            return String(format: "%.0f", totalKm)
        } else if totalKm >= 10 {
            return String(format: "%.1f", totalKm)
        } else {
            return String(format: "%.2f", totalKm)
        }
    }

    var body: some View {
        Group {
            if let widgetData = data {
                mainContent(widgetData)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemIndigo).opacity(0.85)
        }
    }

    // MARK: - Main Content

    private func mainContent(_ widgetData: WidgetData) -> some View {
        HStack(spacing: 16) {
            distanceRing
                .frame(width: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text("This week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))

                weeklyBarChart(widgetData.weeklyDistances)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Distance Ring

    private var distanceRing: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 8)

            // Foreground ring (decorative progress — fills based on 50km weekly goal)
            Circle()
                .trim(from: 0, to: min(totalKm / 50.0, 1.0))
                .stroke(
                    Color.white.opacity(0.5),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Walking icon at top
            VStack(spacing: 0) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: -2)

                // Distance value
                Text(distanceText)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("km")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Weekly Bar Chart

    private func weeklyBarChart(_ distances: [DailyDistance]) -> some View {
        let maxDistance = distances.map(\.distance).max() ?? 1
        let calendar = Calendar.current
        let daySymbols = calendar.veryShortWeekdaySymbols
        // veryShortWeekdaySymbols starts on Sunday (index 0), reorder to start on Monday
        let mondayFirst = Array(daySymbols[1...]) + [daySymbols[0]]

        return VStack(spacing: 4) {
            // Bars
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(distances.enumerated()), id: \.offset) { index, day in
                        let barHeight = maxDistance > 0
                            ? max(CGFloat(day.distance) / CGFloat(maxDistance) * geo.size.height, day.distance > 0 ? 4 : 0)
                            : 0

                        VStack {
                            Spacer(minLength: 0)
                            if day.distance > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.7))
                                    .frame(height: barHeight)
                            } else {
                                // Dashed placeholder for zero-distance days
                                dashedPlaceholder
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 60)

            // Day labels
            HStack(spacing: 4) {
                ForEach(Array(distances.enumerated()), id: \.offset) { index, day in
                    let dayOfWeek = dayOfWeekIndex(from: day.dateString)
                    let isToday = isDateToday(day.dateString)

                    Text(dayOfWeek != nil ? mondayFirst[dayOfWeek!] : "?")
                        .font(.system(size: 9, weight: isToday ? .bold : .regular))
                        .foregroundStyle(.white.opacity(isToday ? 0.9 : 0.5))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var dashedPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 2)
            .padding(.horizontal, 2)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
            Text("No data yet")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text("Open WalkingPad to sync")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// Returns the Monday-based weekday index (0=Monday, 6=Sunday) from a date string.
    private func dayOfWeekIndex(from dateString: String) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return nil }
        let weekday = Calendar.current.component(.weekday, from: date)
        // Calendar weekday: 1=Sunday, 2=Monday, ..., 7=Saturday
        // Convert to Monday-based: Monday=0, Tuesday=1, ..., Sunday=6
        return (weekday + 5) % 7
    }

    private func isDateToday(_ dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}
