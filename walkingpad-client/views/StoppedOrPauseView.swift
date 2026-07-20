import SwiftUI
import CoreBluetooth

struct StoppedOrPausedView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @State private var showYesterdaySync: Bool = false
    @State private var showYesterdayConfirm: Bool = false
    @State private var isSyncingYesterday: Bool = false
    @State private var isStarting: Bool = false
    @State private var startAttempt: Int = 0
    @State private var startTimedOut: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            WorkoutStateView()

            if isStarting {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Starting treadmill…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(.green.opacity(0.1), in: .capsule)
            } else {
                Button(action: startTreadmill) {
                    Text("Start")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .background(.green.opacity(0.1), in: .capsule)

                if startTimedOut {
                    Text("Treadmill didn't respond — try again")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if showYesterdaySync && !isStarting {
                if showYesterdayConfirm {
                    HStack(spacing: 6) {
                        Text("Sync yesterday to Strava?")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { showYesterdayConfirm = false }) {
                            Text("Cancel")
                                .font(.caption2.weight(.medium))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: .capsule)

                        Button(action: {
                            showYesterdayConfirm = false
                            syncYesterday()
                        }) {
                            Text("Sync")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.1), in: .capsule)
                    }
                } else {
                    Button(action: {
                        StravaService.shared.clearUploadResult()
                        showYesterdayConfirm = true
                    }) {
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
                    .background(.orange.opacity(0.1), in: .capsule)
                    .disabled(isSyncingYesterday)
                }
            }
        }
        .onAppear {
            checkYesterday()
            isStarting = false
        }
    }

    /// Sends the wake+start command, then polls the treadmill for status more eagerly
    /// than the regular 5s timer so the UI flips to RunningView as soon as the belt
    /// actually reports movement. Times out after 15s instead of spinning forever.
    private func startTreadmill() {
        isStarting = true
        startTimedOut = false
        startAttempt += 1
        let attempt = startAttempt

        walkingPadService.command()?.wakeAndStart()

        // wakeAndStart waits 1.5s before starting the belt; poll shortly after that
        // and again a few times so we don't sit waiting for the slow timer.
        for delay in [2.0, 3.0, 4.5, 6.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if isStarting && startAttempt == attempt {
                    walkingPadService.command()?.updateStatus()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            if isStarting && startAttempt == attempt {
                isStarting = false
                startTimedOut = true
            }
        }
    }

    private func checkYesterday() {
        let strava = StravaService.shared
        showYesterdaySync = strava.yesterdayNeedsSync
    }

    private func syncYesterday() {
        let notion = NotionService.shared
        let strava = StravaService.shared
        strava.clearUploadResult()

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
