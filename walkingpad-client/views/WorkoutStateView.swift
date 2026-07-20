import SwiftUI
import CoreBluetooth

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

/// Header stats for the popover.
/// While a session is active it shows the current session's distance/steps/time
/// (ticking every second); when idle it shows today's accumulated totals.
struct WorkoutStateView: View {
    @EnvironmentObject var workout: Workout
    @EnvironmentObject var walkingPadService: WalkingPadService

    private var isSessionActive: Bool {
        workout.currentSessionStartTime != nil || workout.isStopping || workout.sessionSaveState != .none
    }

    var body: some View {
        VStack(spacing: 1) {
            if isSessionActive {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let sessionElapsed = workout.currentSessionStartTime.map {
                        Int(timeline.date.timeIntervalSince($0))
                    } ?? 0

                    VStack(spacing: 1) {
                        Text(distanceTextFor(workout.sessionDistance))
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text("\(workout.sessionSteps)")
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text(formatTime(sessionElapsed))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                Text("this session")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            } else {
                // Today's totals: Notion is the source of truth once sessions have
                // synced, but local accumulation covers unsynced walking.
                let todayDistance = max(workout.todayTotalDistance, workout.distance)

                Text(distanceTextFor(todayDistance))
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("\(workout.steps)")
                    if workout.walkingSeconds > 0 {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(formatTime(workout.walkingSeconds))
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                Text(workout.todaySessions.isEmpty ? "today" : "today · \(workout.todaySessions.count) session\(workout.todaySessions.count == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
    }
}
