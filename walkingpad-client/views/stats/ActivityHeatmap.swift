import SwiftUI

/// A year of walking, one square per day (GitHub-style). Squares get greener as a
/// day gets closer to the daily goal; the full green square means the goal was met.
struct ContributionGraph: View {
    let workoutsByDay: [Date: WorkoutSaveData]
    /// Today's live totals, which can lead what has synced to Notion.
    let todayDistance: Int
    let todaySteps: Int
    let todaySeconds: Int
    let currentStreak: Int
    let longestStreak: Int

    @EnvironmentObject var goal: GoalSettings
    @State private var hoveredIndex: Int?

    private static let weeks = 53
    private static let cell: CGFloat = 11
    private static let gap: CGFloat = 3
    private static let labelWidth: CGFloat = 28
    private var pitch: CGFloat { Self.cell + Self.gap }

    private struct Day {
        let date: Date
        let distance: Int
        let steps: Int
        let seconds: Int
        let isFuture: Bool
        let isToday: Bool
    }

    var body: some View {
        let days = buildDays()
        let past = days.filter { !$0.isFuture }
        let activeDays = past.filter { $0.steps > 0 }.count
        let goalDays = past.filter { progress($0) >= 1 }.count

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Last 12 months")
                    .font(.headline)
                Text("\(activeDays) active days")
                Text("\(goalDays) goal days")
                Text("Current streak \(currentStreak)")
                Text("Longest \(longestStreak)")
                Spacer(minLength: 0)
                Text(readout(days: days))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 6) {
                weekdayLabels
                VStack(alignment: .leading, spacing: 5) {
                    monthLabels(days: days)
                    grid(days: days)
                }
            }

            legend
        }
    }

    // MARK: - Grid

    private func grid(days: [Day]) -> some View {
        let width = CGFloat(Self.weeks) * pitch - Self.gap
        let height = 7 * pitch - Self.gap

        return Canvas { context, _ in
            for (index, day) in days.enumerated() where !day.isFuture {
                let column = index / 7
                let row = index % 7
                let rect = CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: Self.cell, height: Self.cell)
                let path = Path(roundedRect: rect, cornerRadius: 3)
                context.fill(path, with: .color(color(for: day)))
                if day.isToday || index == hoveredIndex {
                    context.stroke(path, with: .color(.primary), lineWidth: 1.5)
                }
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let column = Int(location.x / pitch)
                let row = Int(location.y / pitch)
                let index = column * 7 + row
                if column >= 0, column < Self.weeks, row >= 0, row < 7, index < days.count, !days[index].isFuture {
                    hoveredIndex = index
                } else {
                    hoveredIndex = nil
                }
            case .ended:
                hoveredIndex = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Walking history, last 12 months")
        .accessibilityValue(readout(days: days))
    }

    private var weekdayLabels: some View {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        return VStack(alignment: .leading, spacing: Self.gap) {
            // Aligns with the month label row above the grid.
            Color.clear.frame(height: 12)
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 0 ? symbols[(calendar.firstWeekday - 1 + row) % 7] : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth, height: Self.cell, alignment: .leading)
            }
        }
    }

    private func monthLabels(days: [Day]) -> some View {
        let calendar = Calendar.current
        var labels: [(column: Int, text: String)] = []
        for column in 1..<(Self.weeks - 1) {
            let first = days[column * 7].date
            let previous = days[(column - 1) * 7].date
            if calendar.component(.month, from: first) != calendar.component(.month, from: previous) {
                labels.append((column, first.formatted(.dateTime.month(.abbreviated))))
            }
        }

        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: CGFloat(Self.weeks) * pitch - Self.gap, height: 12)
            ForEach(labels, id: \.column) { label in
                Text(label.text)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(label.column) * pitch)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
            Text("0")
            ForEach(0..<6, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Self.levelColor(level))
                    .frame(width: 10, height: 10)
            }
            Text("goal met")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Data

    private func buildDays() -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let first = calendar.date(byAdding: .day, value: -7 * (Self.weeks - 1), to: weekStart) ?? weekStart

        return (0..<(Self.weeks * 7)).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: first) ?? first
            let stored = workoutsByDay[date]
            let isToday = date == today
            return Day(
                date: date,
                distance: isToday ? max(stored?.distance ?? 0, todayDistance) : (stored?.distance ?? 0),
                steps: isToday ? max(stored?.steps ?? 0, todaySteps) : (stored?.steps ?? 0),
                seconds: isToday ? max(stored?.walkingSeconds ?? 0, todaySeconds) : (stored?.walkingSeconds ?? 0),
                isFuture: date > today,
                isToday: isToday
            )
        }
    }

    private func progress(_ day: Day) -> Double {
        goal.progress(distanceMeters: day.distance, steps: day.steps, seconds: day.seconds)
    }

    private func color(for day: Day) -> Color {
        guard day.steps > 0 || day.distance > 0 else { return Self.levelColor(0) }
        let p = progress(day)
        let level = p >= 1 ? 5 : p >= 0.75 ? 4 : p >= 0.5 ? 3 : p >= 0.25 ? 2 : 1
        return Self.levelColor(level)
    }

    /// One hue, light to dark. Adapts to light/dark mode through the system green.
    static func levelColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.08)
        case 1: return Color.green.opacity(0.2)
        case 2: return Color.green.opacity(0.38)
        case 3: return Color.green.opacity(0.56)
        case 4: return Color.green.opacity(0.74)
        default: return Color.green
        }
    }

    private func readout(days: [Day]) -> String {
        let day: Day? = hoveredIndex.flatMap { $0 < days.count ? days[$0] : nil } ?? days.first(where: \.isToday)
        guard let day else { return "" }
        let date = day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        guard day.steps > 0 || day.distance > 0 else { return "\(date) · no walking" }
        let percent = Int((progress(day) * 100).rounded())
        return "\(date) · \(distanceTextFor(day.distance)) · \(day.steps.formatted()) steps · \(percent)% of goal"
    }
}
