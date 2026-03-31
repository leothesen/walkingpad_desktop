import SwiftUI
import CoreBluetooth

struct StoppedOrPausedView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @State private var showYesterdaySync: Bool = false
    @State private var isSyncingYesterday: Bool = false

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
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(.green.opacity(0.1)).interactive(), in: .capsule)

            if showYesterdaySync {
                Button(action: { syncYesterday() }) {
                    HStack(spacing: 4) {
                        if isSyncingYesterday {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(isSyncingYesterday ? "Syncing…" : "Sync Yesterday to Strava")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .glassEffect(.regular.tint(.orange.opacity(0.1)).interactive(), in: .capsule)
                .disabled(isSyncingYesterday)
            }
        }
        .onAppear { checkYesterday() }
    }

    private func checkYesterday() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let strava = appDelegate.stravaService
        showYesterdaySync = strava.yesterdayNeedsSync
    }

    private func syncYesterday() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let notion = appDelegate.notionService
        let strava = appDelegate.stravaService

        isSyncingYesterday = true
        Task {
            let success = await strava.postYesterdayActivity(notionService: notion)
            await MainActor.run {
                isSyncingYesterday = false
                if success {
                    showYesterdaySync = false
                }
            }
        }
    }
}
