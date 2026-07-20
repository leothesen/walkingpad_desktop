import SwiftUI
import Charts

/// Bar chart showing distance over the selected time range.
/// Uses rounded bars with gradient fill. Interactive hover shows detail.
/// Bars and axis labels adapt to the aggregation granularity (day/month/year).
struct DistanceTrendChart: View {
    let points: [DailyPoint]
    let granularity: ChartGranularity
    @Binding var hoveredPoint: DailyPoint?
    /// Normalized X position of the hovered bar (0.0 = left edge, 1.0 = right edge)
    @Binding var hoverFraction: CGFloat

    private var barUnit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .month: return .month
        case .year: return .year
        }
    }

    /// Days covered by the data, used to pick sensible axis labels.
    private var spanDays: Int {
        guard let first = points.first?.date, let last = points.last?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: barUnit),
                    y: .value("Distance", point.distanceKm)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue, .blue.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(4)
                .opacity(hoveredPoint?.date == point.date ? 1.0 : (hoveredPoint != nil ? 0.5 : 1.0))
            }

            if let hovered = hoveredPoint {
                RuleMark(x: .value("Date", hovered.date, unit: barUnit))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis {
            switch granularity {
            case .day:
                if spanDays <= 8 {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .font(.caption2)
                    }
                } else {
                    // 30-day view: labelling every day is unreadable — mark weekly
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
            case .month:
                if spanDays > 370 {
                    // All Time can span years — disambiguate the months
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            .font(.caption2)
                    }
                } else {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow))
                            .font(.caption2)
                    }
                }
            case .year:
                AxisMarks(values: .stride(by: .year)) { _ in
                    AxisValueLabel(format: .dateTime.year())
                        .font(.caption2)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(km >= 100 ? String(format: "%.0f", km) : String(format: "%.1f", km))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotArea = geo[plotFrame]
                            let x = location.x - plotArea.origin.x
                            hoverFraction = plotArea.width > 0 ? x / plotArea.width : 0.5
                            guard let date: Date = proxy.value(atX: x) else { return }
                            hoveredPoint = points.min(by: {
                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                            })
                        case .ended:
                            hoveredPoint = nil
                        }
                    }
            }
        }
    }
}
