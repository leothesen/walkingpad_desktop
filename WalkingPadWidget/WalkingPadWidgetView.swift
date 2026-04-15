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
            Color.indigo.opacity(0.85)
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
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 8)

            Circle()
                .trim(from: 0, to: min(totalKm / 50.0, 1.0))
                .stroke(
                    Color.white.opacity(0.5),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: -2)

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

        return VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<distances.count, id: \.self) { index in
                        barView(
                            distance: distances[index].distance,
                            maxDistance: maxDistance,
                            height: geo.size.height
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 60)

            dayLabelsRow(distances)
        }
    }

    private func barView(distance: Int, maxDistance: Int, height: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 0)
            if distance > 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.7))
                    .frame(height: max(CGFloat(distance) / CGFloat(maxDistance) * height, 4))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 2)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func dayLabelsRow(_ distances: [DailyDistance]) -> some View {
        let calendar = Calendar.current
        let daySymbols = calendar.veryShortWeekdaySymbols
        let mondayFirst = Array(daySymbols[1...]) + [daySymbols[0]]

        return HStack(spacing: 4) {
            ForEach(0..<distances.count, id: \.self) { index in
                let weekdayIndex = dayOfWeekIndex(from: distances[index].dateString)
                let today = isDateToday(distances[index].dateString)
                let label = weekdayIndex != nil ? mondayFirst[weekdayIndex!] : "?"

                Text(label)
                    .font(.system(size: 9, weight: today ? .bold : .regular))
                    .foregroundStyle(.white.opacity(today ? 0.9 : 0.5))
                    .frame(maxWidth: .infinity)
            }
        }
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

    private func dayOfWeekIndex(from dateString: String) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return nil }
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private func isDateToday(_ dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}
