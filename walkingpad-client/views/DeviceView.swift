import SwiftUI
import CoreBluetooth

struct DeviceView: View {
    @EnvironmentObject
    var walkingPadService: WalkingPadService

    @EnvironmentObject
    var workout: Workout

    var body: some View {
        if (!walkingPadService.isConnected()) {
            return AnyView(WaitingForTreadmillView())
        }
        // Keep showing RunningView while a session is active, stopping, or save/upload in progress
        if workout.currentSessionStartTime != nil || workout.isStopping || workout.sessionSaveState != .none {
            return AnyView(RunningView())
        }
        if (walkingPadService.lastStatus()?.speed ?? 0 == 0) {
            return AnyView(StoppedOrPausedView())
        }
        return AnyView(RunningView())
    }
}
