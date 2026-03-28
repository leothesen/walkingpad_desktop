import SwiftUI
import Charts

/// Smooth area chart showing distance over the selected time range.
/// Gradient fill under the line with interactive hover to show daily detail.
struct DistanceTrendChart: View {
    let points: [DailyPoint]
    let isMonthly: Bool
    @Binding var hoveredPoint: DailyPoint?

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: isMonthly ? .month : .day),
                    y: .value("Distance", point.distanceKm)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date, unit: isMonthly ? .month : .day),
                    y: .value("Distance", point.distanceKm)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            if let hovered = hoveredPoint {
                RuleMark(x: .value("Date", hovered.date, unit: isMonthly ? .month : .day))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                PointMark(
                    x: .value("Date", hovered.date, unit: isMonthly ? .month : .day),
                    y: .value("Distance", hovered.distanceKm)
                )
                .foregroundStyle(.blue)
                .symbolSize(40)
            }
        }
        .chartXAxis {
            if isMonthly {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(String(format: "%.1f", km))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                            guard let date: Date = proxy.value(atX: x) else { return }
                            // Find closest point
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
