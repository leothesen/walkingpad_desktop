import SwiftUI
import Charts

/// Root view for the floating stats window.
/// Layout hierarchy: hero distance → trend chart → supporting metrics → consistency streak.
struct StatsWindowView: View {
    @StateObject var viewModel: StatsViewModel

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 14) {
                // Time range selector
                Picker("Range", selection: $viewModel.selectedRange.animation(.spring(duration: 0.35))) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                // 1. Hero: Distance
                heroDistance

                // 2. Trend chart
                trendChart

                // 3. Supporting metrics
                supportingMetrics

                // 4. Consistency streak
                consistencySection
            }
            .padding(16)
        }
    }

    // MARK: - Hero Distance

    private var heroDistance: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(viewModel.distanceText)
                    .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                Text(viewModel.distanceUnit)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let trend = viewModel.distanceTrend {
                trendBadge(trend)
            }

            // Hover detail overlay
            if let hovered = viewModel.hoveredPoint {
                HStack(spacing: 12) {
                    Text(hovered.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    Text(String(format: "%.2f km", hovered.distanceKm))
                        .fontWeight(.medium)
                    Text("\(hovered.steps) steps")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func trendBadge(_ percent: Double) -> some View {
        let isUp = percent >= 0
        return HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
            Text(String(format: "%.0f%%", abs(percent)))
                .font(.caption.weight(.medium).monospacedDigit())
            Text("vs prev period")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isUp ? .green : .red)
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            DistanceTrendChart(
                points: viewModel.dailyPoints,
                isMonthly: viewModel.selectedRange == .allTime,
                hoveredPoint: $viewModel.hoveredPoint
            )
            .frame(height: 140)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Supporting Metrics

    private var supportingMetrics: some View {
        HStack(spacing: 8) {
            MetricCard(
                icon: "figure.walk",
                value: formattedSteps,
                label: "Steps"
            )
            MetricCard(
                icon: "clock",
                value: viewModel.timeText,
                label: "Time"
            )
            MetricCard(
                icon: "speedometer",
                value: viewModel.avgSpeedText,
                label: "km/h avg"
            )
            MetricCard(
                icon: "repeat",
                value: "\(viewModel.totalSessions)",
                label: "Sessions"
            )
        }
    }

    private var formattedSteps: String {
        let steps = viewModel.totalSteps
        if steps >= 10000 {
            return String(format: "%.1fk", Double(steps) / 1000.0)
        }
        return "\(steps)"
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        ConsistencyStreak(
            activeDays: viewModel.activeDays,
            totalDays: viewModel.periodDays,
            workouts: viewModel.filteredWorkouts
        )
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Metric Card

/// Compact supporting metric with SF Symbol, value, and label.
struct MetricCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}
