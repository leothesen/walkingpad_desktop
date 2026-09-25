import SwiftUI

/// No treadmill connected: today's progress stays visible, only the Start slot changes.
struct WaitingForTreadmillView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodayGoalHeader()

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for WalkingPad")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .glassEffect(.regular, in: .capsule)

            Text("Turn the treadmill on. It connects automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
