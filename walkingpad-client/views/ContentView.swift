import SwiftUI

/// Root view for the status bar popover.
/// Shows DeviceView when a treadmill is connected, otherwise WaitingForTreadmillView.
struct ContentView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    private var stravaService: StravaService? {
        (NSApp.delegate as? AppDelegate)?.stravaService
    }

    static func relativeSyncTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let time = timeFormatter.string(from: date).lowercased()

        if calendar.isDateInToday(date) {
            return "today at \(time)"
        } else if calendar.isDateInYesterday(date) {
            return "yesterday at \(time)"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MMM d"
            return "\(dayFormatter.string(from: date)) at \(time)"
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(spacing: 6) {
                if walkingPadService.isConnected() {
                    DeviceView()
                } else {
                    WaitingForTreadmillView()
                }

                if let strava = stravaService {
                    StravaInfoBox(stravaService: strava)
                }

                Divider().opacity(0.15)

                FooterView()
            }
            .padding(10)
        }
    }
}

/// Info box showing Strava sync status — unsynced sessions and upload results.
struct StravaInfoBox: View {
    @ObservedObject var stravaService: StravaService

    var body: some View {
        let hasUnsynced = stravaService.unsyncedSessionCount > 0 && stravaService.unsyncedDateLabel != nil
        let hasResult = stravaService.uploadResultMessage != nil
        let hasSyncTime = stravaService.isConnected && stravaService.lastStravaSync != nil

        if hasUnsynced || hasResult || hasSyncTime {
            VStack(spacing: 3) {
                if let message = stravaService.uploadResultMessage {
                    HStack(spacing: 4) {
                        Image(systemName: stravaService.uploadResultIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(stravaService.uploadResultIsError ? .red : .green)
                        Text(message)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(stravaService.uploadResultIsError ? .red : .green)
                    }
                }

                if hasUnsynced {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("\(stravaService.unsyncedSessionCount) unsynced session\(stravaService.unsyncedSessionCount == 1 ? "" : "s") from \(stravaService.unsyncedDateLabel!)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                if hasSyncTime, let syncDate = stravaService.lastStravaSync {
                    Text("Last sync: \(ContentView.relativeSyncTime(syncDate))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }
    }
}
