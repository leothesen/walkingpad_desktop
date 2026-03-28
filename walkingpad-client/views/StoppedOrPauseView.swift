import SwiftUI
import CoreBluetooth

struct StoppedOrPausedView: View {

    @EnvironmentObject
    var walkingPadService: WalkingPadService

    var body: some View {
        VStack(spacing: 10) {
            WorkoutStateView()

            Button(action: {
                self.walkingPadService.command()?.start()
            }) {
                Text("Start")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.green.opacity(0.15)).interactive(), in: .capsule)
        }
    }
}
