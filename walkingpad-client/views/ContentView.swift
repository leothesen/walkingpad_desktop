import SwiftUI

/// Root view for the status bar popover.
/// Shows DeviceView when a treadmill is connected, otherwise WaitingForTreadmillView.
struct ContentView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 12) {
                if walkingPadService.isConnected() {
                    DeviceView()
                } else {
                    WaitingForTreadmillView()
                }

                Spacer()

                FooterView()
            }
            .padding(12)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
