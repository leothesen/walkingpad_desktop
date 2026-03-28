import SwiftUI
import CoreBluetooth

/// Formats a distance value for display. Shows meters below 10km, km above.
/// Note: threshold is 10,000m (10km) rather than the more common 1,000m — see KNOWN_ISSUES.md #15.
func distanceTextFor(_ meters: Int) -> String {
    if (meters < 10000) {
        return "\(meters) m"
    }
    return String(format: "%.00f km", Double(meters) / 1000)
}


func stepsTextFor(_ steps: Int) -> String {
    return String(steps)
}

func formatTime(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated

    return formatter.string(from: TimeInterval(seconds)) ?? ""
    
}


struct WorkoutStateView: View {
    @EnvironmentObject
    var workout: Workout

    @EnvironmentObject
    var walkingPadService: WalkingPadService

    var body: some View {
        let statusSeconds = walkingPadService.lastStatus()?.walkingTimeSeconds ?? 0
        VStack(spacing: 4) {
            Text("\(formatTime(workout.walkingSeconds)) (\(formatTime(statusSeconds)))")
                .font(.headline)
            Text("\(workout.steps) Steps")
                .font(.title3.weight(.semibold))
            Text("\(distanceTextFor(workout.distance))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
