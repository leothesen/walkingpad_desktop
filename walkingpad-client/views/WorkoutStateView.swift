import SwiftUI

/// Formats a distance value for display. Switches to km at 1000m.
func distanceTextFor(_ meters: Int) -> String {
    if meters < 1000 {
        return "\(meters) m"
    }
    return String(format: "%.2f km", Double(meters) / 1000)
}

func formatTime(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: TimeInterval(seconds)) ?? ""
}

/// "2h 05m", "7m 12s", "45s".
func compactDuration(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
    if minutes > 0 { return "\(minutes)m \(String(format: "%02d", seconds))s" }
    return "\(seconds)s"
}

/// Session timer: "7:12", "1:02:03".
func timerText(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

/// One-tap speeds, in km/h. Shared by the start chip and the walking controls.
enum SpeedPresets {
    static let all: [(label: String, kmh: Double)] = [
        ("Quiet", 1.5),
        ("Steady", 3.5),
        ("Fast", 5.0),
    ]
    static let minKmh = 0.5
    static let maxKmh = 8.0
    static let step = 0.5
}

/// Thin progress bar toward the daily goal. `liveFraction` is the part contributed
/// by the session in progress, drawn in a lighter shade at the leading edge.
struct GoalProgressBar: View {
    var fraction: Double
    var liveFraction: Double = 0

    var body: some View {
        GeometryReader { geo in
            let total = min(max(fraction, 0), 1)
            let settled = min(max(fraction - liveFraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(Color.green.opacity(0.5)).frame(width: geo.size.width * total)
                Capsule().fill(Color.green).frame(width: geo.size.width * settled)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Daily goal")
        .accessibilityValue("\(Int((min(fraction, 9.99) * 100).rounded())) percent")
    }
}

/// Today's amount against the goal, with its progress bar.
/// Used by the idle, goal-reached and disconnected states.
struct TodayGoalHeader: View {
    @EnvironmentObject var workout: Workout
    @EnvironmentObject var goal: GoalSettings
    /// When set, shows how much is left and roughly how long it takes at this speed.
    var estimateSpeedKmh: Double? = nil

    var body: some View {
        let distance = workout.todayDistance
        let progress = goal.progress(distanceMeters: distance, steps: workout.steps, seconds: workout.walkingSeconds)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(amountText)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                Text("/ \(goal.label)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if progress >= 1 {
                    Label("Goal", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GoalProgressBar(fraction: progress)

            if let speed = estimateSpeedKmh, progress < 1 {
                Text(remainingText(speedKmh: speed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var amountText: String {
        let amount = goal.amount(distanceMeters: workout.todayDistance, steps: workout.steps, seconds: workout.walkingSeconds)
        switch goal.kind {
        case .distance: return String(format: "%.2f", amount)
        case .steps: return Int(amount).formatted()
        case .time: return String(Int(amount))
        }
    }

    private func remainingText(speedKmh: Double) -> String {
        let amount = goal.amount(distanceMeters: workout.todayDistance, steps: workout.steps, seconds: workout.walkingSeconds)
        let remaining = max(0, goal.value - amount)
        switch goal.kind {
        case .distance:
            let eta = goal.timeToGoal(distanceMeters: workout.todayDistance, steps: workout.steps, seconds: workout.walkingSeconds, speedKmh: speedKmh)
            let base = String(format: "%.2f km to go", remaining)
            guard let eta else { return base }
            return base + " · about \(compactDuration(eta)) at " + String(format: "%.1f km/h", speedKmh)
        case .steps:
            return "\(Int(remaining).formatted()) steps to go"
        case .time:
            return "\(Int(remaining.rounded(.up))) min to go"
        }
    }
}

/// The day's other numbers, skipping whichever one the goal already shows.
struct TodayStatsRow: View {
    @EnvironmentObject var workout: Workout
    @EnvironmentObject var goal: GoalSettings

    var body: some View {
        HStack(spacing: 12) {
            if goal.kind != .distance {
                Text(distanceTextFor(workout.todayDistance))
            }
            if goal.kind != .steps {
                Text("\(workout.steps.formatted()) steps")
            }
            if goal.kind != .time && workout.walkingSeconds > 0 {
                Text(compactDuration(TimeInterval(workout.walkingSeconds)))
            }
            if !workout.todaySessions.isEmpty {
                Text("\(workout.todaySessions.count) walk\(workout.todaySessions.count == 1 ? "" : "s")")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
