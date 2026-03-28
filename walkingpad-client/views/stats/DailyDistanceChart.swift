import SwiftUI
import Charts

/// Bar chart showing distance over time (daily or monthly depending on selected range).
struct DailyDistanceChart: View {
    let bars: [DailyBar]
    let isMonthly: Bool

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Date", bar.date, unit: isMonthly ? .month : .day),
                y: .value("Distance", Double(bar.distance) / 1000.0)
            )
            .foregroundStyle(.blue.gradient)
            .cornerRadius(4)
        }
        .chartYAxisLabel("km")
        .chartXAxis {
            if isMonthly {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                    AxisGridLine()
                }
            } else {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    AxisGridLine()
                }
            }
        }
    }
}
