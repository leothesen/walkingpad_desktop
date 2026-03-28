import SwiftUI
import Charts

/// Heatmap showing walking activity by day-of-week (x) and time-of-day (y).
/// Color intensity represents distance covered in each 2-hour block.
struct ActivityHeatmap: View {
    let cells: [HeatmapCell]
    let maxDistance: Double

    private let hourLabels: [Int: String] = [
        6: "6am", 8: "8am", 10: "10am", 12: "12pm",
        14: "2pm", 16: "4pm", 18: "6pm", 20: "8pm", 22: "10pm"
    ]

    private let dayOrder = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        Chart(cells) { cell in
            RectangleMark(
                x: .value("Day", reorderDay(cell.dayLabel)),
                y: .value("Hour", hourLabels[cell.hour] ?? "\(cell.hour)"),
                width: .ratio(0.9),
                height: .ratio(0.9)
            )
            .foregroundStyle(cellColor(cell.distance))
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: dayOrder) { value in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(values: Array(hourLabels.values.sorted())) { value in
                AxisValueLabel()
            }
        }
    }

    /// Reorder Sunday-first weekday to Monday-first for display.
    private func reorderDay(_ label: String) -> String {
        label
    }

    private func cellColor(_ distance: Double) -> Color {
        guard maxDistance > 0 else { return .blue.opacity(0.05) }
        let intensity = min(distance / maxDistance, 1.0)
        if intensity == 0 {
            return .blue.opacity(0.05)
        }
        return .blue.opacity(0.15 + intensity * 0.85)
    }
}
