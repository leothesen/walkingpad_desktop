import SwiftUI
import CoreBluetooth

struct StoppedOrPausedView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService

    var body: some View {
        VStack(spacing: 6) {
            WorkoutStateView()

            Button(action: {
                walkingPadService.command()?.start()
            }) {
                Text("Start")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(.green.opacity(0.1)).interactive(), in: .capsule)
        }
    }
}
