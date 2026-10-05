import SwiftUI
import WidgetKit

/// Today's goal ring on the left, a grid of day dots filling the rest.
///
/// Each dot is one day (columns are weeks, newest on the right). A dot grows and
/// brightens with the share of the daily goal walked; full size means the goal was met.
/// Colors are semantic or accentable so the widget follows tinted and clear desktop
/// styles like the system widgets do.
struct WalkingPadWidgetView: View {
    let entry: WalkingPadEntry

    var body: some View {
        Group {
            if let data = entry.widgetData {
                content(data)
            } else {
                emptyState
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func content(_ data: WidgetData) -> some View {
        let today = data.day(for: entry.date)
        let progress = data.goal.progress(of: today)

        return GeometryReader { geo in
            let spacing: CGFloat = 14
            let ringSize = geo.size.height
            let pitch = geo.size.height / 7
            let dotSize = pitch * 0.86
            let gridWidth = geo.size.width - ringSize - spacing
            let weeks = min(WidgetData.historyDays / 7, max(1, Int((gridWidth + pitch - dotSize) / pitch)))

            HStack(spacing: spacing) {
                GoalRing(amount: data.goal.amount(of: today), progress: progress, goal: data.goal, size: ringSize)
                Spacer(minLength: 0)
                DotGrid(
                    columns: data.grid(weeks: weeks, today: entry.date),
                    goal: data.goal,
                    today: today.dateString,
                    dotSize: dotSize,
                    gap: pitch - dotSize
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today \(data.goal.format(data.goal.amount(of: today))) of \(data.goal.formattedValue) \(data.goal.unit)")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "figure.walk")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No walks yet")
                .font(.headline)
            Text("Open WalkingPad to sync")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Today's amount inside a ring that fills toward the daily goal.
private struct GoalRing: View {
    let amount: Double
    let progress: Double
    let goal: WidgetGoal
    let size: CGFloat

    var body: some View {
        let line = size * 0.09

        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(Color.green, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: 0) {
                Text(goal.format(amount))
                    .font(.system(size: size * 0.21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("of \(goal.formattedValue) \(goal.unit)")
                    .font(.system(size: size * 0.09, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, line * 1.5)
        }
        .padding(line / 2)
        .frame(width: size, height: size)
    }
}

/// Weeks as columns, oldest first; nil days (later this week) are drawn as outlines.
private struct DotGrid: View {
    let columns: [[WidgetDay?]]
    let goal: WidgetGoal
    let today: String
    let dotSize: CGFloat
    let gap: CGFloat

    var body: some View {
        HStack(spacing: gap) {
            ForEach(columns.indices, id: \.self) { week in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        let day = columns[week][row]
                        DayDot(
                            progress: day.map { goal.progress(of: $0) },
                            isToday: day?.dateString == today,
                            size: dotSize
                        )
                    }
                }
            }
        }
    }
}

private struct DayDot: View {
    /// nil for a day that hasn't happened yet.
    let progress: Double?
    let isToday: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            if let progress = progress {
                if progress > 0 {
                    let fraction = min(progress, 1)
                    Circle()
                        .fill(Color.green.opacity(0.45 + 0.55 * fraction))
                        .frame(width: size * (0.32 + 0.68 * fraction), height: size * (0.32 + 0.68 * fraction))
                        .widgetAccentable()
                } else {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: max(3, size * 0.2), height: max(3, size * 0.2))
                }
            } else {
                Circle()
                    .strokeBorder(.quaternary, lineWidth: 1)
            }

            if isToday {
                Circle()
                    .strokeBorder(.primary, lineWidth: 1.3)
                    .padding(-1.5)
            }
        }
        .frame(width: size, height: size)
    }
}
