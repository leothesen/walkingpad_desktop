import SwiftUI
import CoreBluetooth

struct StoppedOrPausedView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @State private var showYesterdaySync: Bool = false
    @State private var showYesterdayConfirm: Bool = false
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
            .background(.green.opacity(0.1), in: .capsule)

            if showYesterdaySync {
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
        .onAppear { checkYesterday() }
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
