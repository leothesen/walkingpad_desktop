import SwiftUI
import Charts
import Sparkle

/// Root view for the floating stats window.
/// Layout hierarchy: hero distance → trend chart → supporting metrics → consistency streak.
struct StatsWindowView: View {
    @StateObject var viewModel: StatsViewModel
    var walkingPadService: WalkingPadService?
    var notionService: NotionService
    var stravaService: StravaService
    @State private var showDebug = false
    @State private var hoverFraction: CGFloat = 0.5
    @State private var selectedRange: TimeRange = .week

    var body: some View {
        VStack(spacing: 14) {
                // Time range selector + debug toggle
                HStack {
                    Picker(selection: $selectedRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    } label: {
                        SwiftUI.EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: selectedRange) {
                        DispatchQueue.main.async {
                            viewModel.selectedRange = selectedRange
                            viewModel.hoveredPoint = nil
                        }
                    }

                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Button(action: {
                        (NSApp.delegate as? AppDelegate)?.checkForUpdates()
                    }) {
                        Image(systemName: "arrow.down.circle")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Check for updates")

                    Button(action: { showDebug.toggle() }) {
                        Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
                            .font(.body)
                            .foregroundStyle(showDebug ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle debug panel")
                }

                if viewModel.isLoading {
                    // Loading state — replaces content while fetching
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Loading from Notion…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    Spacer()
                } else {
                    // 1. Hero: Distance
                    heroDistance

                    // 2. Trend chart
                    trendChart

                    // 3. Supporting metrics
                    supportingMetrics

                    // 4. Consistency streak
                    consistencySection
                }

                // 5. Debug panel (expandable)
                if showDebug, let service = walkingPadService {
                    Divider().opacity(0.3)
                    DebugView(
                        workouts: viewModel.allWorkouts,
                        walkingPadService: service,
                        notionService: notionService,
                        stravaService: stravaService
                    )
                    .frame(minHeight: 200)
                }
            }
            .padding(16)
            .frame(minWidth: 460, minHeight: 400)
    }

    // MARK: - Hero Distance

    private var heroDistance: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(viewModel.distanceText)
                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
            Text(viewModel.distanceUnit)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        DistanceTrendChart(
            points: viewModel.dailyPoints,
            isMonthly: viewModel.selectedRange == .allTime,
            hoveredPoint: $viewModel.hoveredPoint,
            hoverFraction: $hoverFraction
        )
        .frame(height: 140)
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay(alignment: .top) {
            if let hovered = viewModel.hoveredPoint {
                HStack(spacing: 6) {
                    Text(hovered.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    Text("·").foregroundStyle(.quaternary)
                    Text(String(format: "%.2f km", hovered.distanceKm))
                        .fontWeight(.semibold)
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(hovered.steps) steps")
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .offset(y: -14)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
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
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
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
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
    }
}
