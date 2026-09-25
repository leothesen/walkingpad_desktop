import SwiftUI
import Charts
import Sparkle

/// Root view for the stats window.
/// Layout: range switch → period total + today's goal → a year of walking →
/// distance chart + highlights → optional debug panel.
struct StatsWindowView: View {
    @StateObject var viewModel: StatsViewModel
    var walkingPadService: WalkingPadService?
    var notionService: NotionService
    var stravaService: StravaService

    @EnvironmentObject var goal: GoalSettings
    @EnvironmentObject var workout: Workout

    @State private var showDebug = false
    @State private var showGoalEditor = false
    @State private var hoverFraction: CGFloat = 0.5
    /// Local copy for the Picker — binding it to the @Published property directly
    /// triggers "Publishing changes from within view updates".
    @State private var selectedRange: TimeRange = .month

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                toolbar

                if viewModel.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading from Notion…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 480)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        periodCard
                        todayCard
                            .frame(width: 300)
                    }

                    ContributionGraph(
                        workoutsByDay: viewModel.workoutsByDay,
                        todayDistance: workout.todayDistance,
                        todaySteps: workout.steps,
                        todaySeconds: workout.walkingSeconds,
                        currentStreak: viewModel.currentStreak,
                        longestStreak: viewModel.longestStreak
                    )
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))

                    HStack(alignment: .top, spacing: 16) {
                        chartCard
                        highlightsCard
                            .frame(width: 300)
                    }
                }

                if showDebug, let service = walkingPadService {
                    DebugView(
                        workouts: viewModel.allWorkouts,
                        walkingPadService: service,
                        notionService: notionService,
                        stravaService: stravaService
                    )
                    .frame(minHeight: 320)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 900, minHeight: 720)
        .onAppear {
            DispatchQueue.main.async {
                viewModel.selectedRange = selectedRange
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Room for the window's traffic lights (full-size content view).
            Color.clear.frame(width: 64, height: 1)

            Spacer()

            Picker(selection: $selectedRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            } label: {
                SwiftUI.EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .onChange(of: selectedRange) {
                DispatchQueue.main.async {
                    viewModel.selectedRange = selectedRange
                    viewModel.hoveredPoint = nil
                }
            }

            Spacer()

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button(action: { AppDelegate.checkForUpdates() }) {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Check for updates")

            Button(action: { showDebug.toggle() }) {
                Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Toggle debug panel")
        }
        .frame(height: 36)
    }

    // MARK: - Period

    private var rangeLabel: String {
        switch viewModel.selectedRange {
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .year: return "Last 12 months"
        }
    }

    private var periodCard: some View {
        HStack(alignment: .bottom, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text(rangeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(viewModel.distanceText)
                        .font(.system(size: 50, weight: .bold, design: .rounded).monospacedDigit())
                    Text(viewModel.distanceUnit)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let trend = viewModel.distanceTrend {
                    let isUp = trend >= 0
                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                        Text(String(format: "%+.0f%% %@", trend, viewModel.trendComparisonLabel))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(isUp ? .green : .red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((isUp ? Color.green : Color.red).opacity(0.14), in: Capsule())
                }
            }

            Spacer(minLength: 0)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow {
                    metric(formattedSteps, "steps")
                    metric(viewModel.timeText, "walking")
                }
                GridRow {
                    metric("\(viewModel.goalDays(goal: goal)) of \(viewModel.periodDays)", "goal days")
                    metric(viewModel.dailyAvgText, "per active day")
                }
            }
            .padding(.bottom, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var formattedSteps: String {
        let steps = viewModel.totalSteps
        if steps >= 10000 {
            return String(format: "%.1fk", Double(steps) / 1000.0)
        }
        return steps.formatted()
    }

    // MARK: - Today

    private var todayCard: some View {
        let progress = goal.progress(distanceMeters: workout.todayDistance, steps: workout.steps, seconds: workout.walkingSeconds)
        let amount = goal.amount(distanceMeters: workout.todayDistance, steps: workout.steps, seconds: workout.walkingSeconds)

        return HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(progress, 1))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(goal.kind == .distance ? String(format: "%.2f", amount) : goal.kind.format(amount))
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text("/ \(goal.label)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button {
                    showGoalEditor = true
                } label: {
                    Label("Daily goal", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.glass)
                .popover(isPresented: $showGoalEditor, arrowEdge: .bottom) {
                    GoalEditor(recentWorkouts: recentMonth, isPresented: $showGoalEditor)
                        .environmentObject(goal)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minHeight: 150)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var recentMonth: [WorkoutSaveData] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return viewModel.allWorkouts.filter { $0.date >= cutoff }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.granularity == .day ? "Daily distance" : "Monthly distance")
                    .font(.headline)
                Spacer()
                if let hovered = viewModel.hoveredPoint {
                    HStack(spacing: 6) {
                        hoveredDateText(hovered.date)
                        Text("·").foregroundStyle(.tertiary)
                        Text(String(format: "%.2f km", hovered.distanceKm))
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(hovered.steps.formatted()) steps")
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                }
            }

            DistanceTrendChart(
                points: viewModel.dailyPoints,
                granularity: viewModel.granularity,
                goalKm: goal.kind == .distance && viewModel.granularity == .day ? goal.value : nil,
                hoveredPoint: $viewModel.hoveredPoint,
                hoverFraction: $hoverFraction
            )
            .frame(height: 180)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Formats the hovered bar's date at the chart's granularity.
    @ViewBuilder
    private func hoveredDateText(_ date: Date) -> some View {
        switch viewModel.granularity {
        case .day:
            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .month:
            Text(date, format: .dateTime.month(.wide).year())
        case .year:
            Text(date, format: .dateTime.year())
        }
    }

    // MARK: - Highlights

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.headline)

            highlight("Best day", viewModel.bestDay == nil ? "—" : "\(viewModel.bestDayText) · \(viewModel.bestDayDateText.replacingOccurrences(of: "Best · ", with: ""))")
            highlight("Avg speed", "\(viewModel.avgSpeedText) km/h")
            highlight("Walks", "\(viewModel.totalSessions)")
            highlight("Longest walk", viewModel.longestSessionSeconds.map { compactDuration($0) } ?? "—")

            Spacer(minLength: 0)

            Divider()

            HStack(spacing: 12) {
                statusDot(notionService.isConfigured, "Notion")
                statusDot(stravaService.isConnected, "Strava")
                Spacer(minLength: 0)
                Text(viewModel.dataSource)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(minHeight: 236, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func highlight(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
    }

    private func statusDot(_ ok: Bool, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ok ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(ok ? label : "\(label) off")
        }
    }
}

// MARK: - Goal editor

/// Sets the daily goal: distance, steps or time, with presets and a hint from the
/// last 30 days so the number is grounded in what you actually walk.
struct GoalEditor: View {
    @EnvironmentObject var goal: GoalSettings
    let recentWorkouts: [WorkoutSaveData]
    @Binding var isPresented: Bool

    @State private var kind: GoalSettings.Kind = .distance
    @State private var values: [GoalSettings.Kind: Double] = [:]

    private var value: Double { values[kind] ?? kind.defaultValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily goal")
                    .font(.title3.weight(.bold))
                Text("Drives the ring in the menu bar and the green in your history.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("Goal type", selection: $kind) {
                ForEach(GoalSettings.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button { set(value - kind.step) } label: {
                    Image(systemName: "minus").frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Decrease goal")

                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(kind.format(value))
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    Text(kind.unit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button { set(value + kind.step) } label: {
                    Image(systemName: "plus").frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Increase goal")
            }

            HStack(spacing: 6) {
                ForEach(kind.presets, id: \.self) { preset in
                    if abs(preset - value) < 0.001 {
                        Button(kind.format(preset)) { set(preset) }
                            .buttonStyle(.glassProminent)
                            .tint(.green)
                    } else {
                        Button(kind.format(preset)) { set(preset) }
                            .buttonStyle(.glass)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity)
                Button("Save goal") {
                    goal.set(kind: kind, value: value)
                    isPresented = false
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            kind = goal.kind
            values[goal.kind] = goal.value
        }
    }

    private func set(_ newValue: Double) {
        values[kind] = max(kind.step, newValue)
    }

    /// What the last 30 days say about this goal.
    private var hint: String {
        let amounts: [Double] = recentWorkouts.filter { $0.steps > 0 }.map { w in
            switch kind {
            case .distance: return Double(w.distance) / 1000
            case .steps: return Double(w.steps)
            case .time: return Double(w.walkingSeconds) / 60
            }
        }
        guard !amounts.isEmpty else {
            return "No walks in the last 30 days yet. You can change this any time."
        }
        let average = amounts.reduce(0, +) / Double(amounts.count)
        let hits = amounts.filter { $0 >= value }.count
        return "Your last 30 days averaged \(kind.format((average * 10).rounded() / 10)) \(kind.unit) on active days. This goal would have been met on \(hits) of \(amounts.count)."
    }
}
