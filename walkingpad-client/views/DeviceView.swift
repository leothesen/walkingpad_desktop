import SwiftUI
import CoreBluetooth

/// Picks the popover state. Each state answers one question:
/// - Walking: how's this session going, and how fast?
/// - Session ended: am I done for today?
/// - Idle / goal reached: how's my day going?
/// - No treadmill: same as idle, with the Start slot waiting for a connection.
struct DeviceView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    var body: some View {
        let connected = walkingPadService.isConnected()
        let beltRunning = (walkingPadService.lastStatus()?.speed ?? 0) > 0

        if connected && (workout.currentSessionStartTime != nil || beltRunning) {
            WalkingView()
        } else if let session = workout.recentSession {
            SessionEndedView(session: session)
        } else if connected {
            VStack(alignment: .leading, spacing: 12) {
                YesterdayStravaBanner()
                IdleView()
                FooterView()
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                YesterdayStravaBanner()
                WaitingForTreadmillView()
                FooterView()
            }
        }
    }
}

/// The one "needs attention" pattern: yesterday has walks that never reached Strava.
struct YesterdayStravaBanner: View {
    @ObservedObject private var strava = StravaService.shared
    @State private var isPosting = false

    var body: some View {
        if strava.isConnected && strava.yesterdayNeedsSync {
            HStack(spacing: 8) {
                Text("Yesterday's walks aren't on Strava")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
                if isPosting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Post") { postYesterday() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .tint(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
        }
    }

    private func postYesterday() {
        isPosting = true
        StravaService.shared.clearUploadResult()
        Task {
            _ = await StravaService.shared.postYesterdayActivity(notionService: NotionService.shared)
            await MainActor.run { isPosting = false }
        }
    }
}
