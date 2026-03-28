import SwiftUI
import Charts

/// Root view for the floating stats window.
struct StatsWindowView: View {
    @StateObject var viewModel: StatsViewModel

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                // Time range picker
                Picker("Range", selection: $viewModel.selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                // Summary cards
                HStack(spacing: 10) {
                    StatCard(title: "Distance", value: viewModel.distanceText)
                    StatCard(title: "Steps", value: "\(viewModel.totalSteps)")
                    StatCard(title: "Time", value: viewModel.timeText)
                    StatCard(title: "Sessions", value: "\(viewModel.totalSessions)")
                }

                // Distance bar chart
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedRange == .allTime ? "Monthly Distance" : "Daily Distance")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    DailyDistanceChart(
                        bars: viewModel.dailyBars,
                        isMonthly: viewModel.selectedRange == .allTime
                    )
                    .frame(height: 120)
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))

                // Activity heatmap
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity Pattern")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    ActivityHeatmap(
                        cells: viewModel.heatmapData,
                        maxDistance: viewModel.maxHeatmapDistance
                    )
                    .frame(height: 120)
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
            .padding(16)
        }
    }
}

/// A single summary metric card with glass styling.
struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}
