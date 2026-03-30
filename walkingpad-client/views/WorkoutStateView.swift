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

struct WorkoutStateView: View {
    @EnvironmentObject var workout: Workout
    @EnvironmentObject var walkingPadService: WalkingPadService

    var body: some View {
        VStack(spacing: 1) {
            Text(distanceTextFor(workout.distance))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("\(workout.steps)")
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(formatTime(workout.walkingSeconds))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}
