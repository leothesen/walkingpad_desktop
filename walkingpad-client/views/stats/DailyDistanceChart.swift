import SwiftUI
import Charts

/// Bar chart showing distance over the selected time range.
/// Uses rounded bars with gradient fill. Interactive hover shows daily detail.
struct DistanceTrendChart: View {
    let points: [DailyPoint]
    let isMonthly: Bool
    @Binding var hoveredPoint: DailyPoint?
    /// Normalized X position of the hovered bar (0.0 = left edge, 1.0 = right edge)
    @Binding var hoverFraction: CGFloat

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: isMonthly ? .month : .day),
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
                RuleMark(x: .value("Date", hovered.date, unit: isMonthly ? .month : .day))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis {
            if isMonthly {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.caption2)
                }
            } else {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
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
                        Text(String(format: "%.1f", km))
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
