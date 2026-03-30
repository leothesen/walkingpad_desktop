import SwiftUI

/// Root view for the status bar popover.
/// Shows DeviceView when a treadmill is connected, otherwise WaitingForTreadmillView.
struct ContentView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(spacing: 6) {
                if walkingPadService.isConnected() {
                    DeviceView()
                } else {
                    WaitingForTreadmillView()
                }

                Divider().opacity(0.15)

                FooterView()
            }
            .padding(10)
        }
    }
}
