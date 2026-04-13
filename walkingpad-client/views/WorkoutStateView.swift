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

/// Shows current session distance + steps + time (not daily accumulation).
struct WorkoutStateView: View {
    @EnvironmentObject var workout: Workout
    @EnvironmentObject var walkingPadService: WalkingPadService

    var body: some View {
        let sessionElapsed = workout.currentSessionStartTime.map {
            Int(Date().timeIntervalSince($0))
        } ?? 0

        VStack(spacing: 1) {
            Text(distanceTextFor(workout.sessionDistance))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("\(workout.sessionSteps)")
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(formatTime(sessionElapsed))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
    }
}
