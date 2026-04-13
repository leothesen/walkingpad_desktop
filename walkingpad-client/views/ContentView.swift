import SwiftUI

/// Root view for the status bar popover.
/// Shows DeviceView when a treadmill is connected, otherwise WaitingForTreadmillView.
struct ContentView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    private var stravaService: StravaService? {
        (NSApp.delegate as? AppDelegate)?.stravaService
    }

    private static func relativeSyncTime(_ date: Date) -> String {
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

                Divider().opacity(0.15)

                if let strava = stravaService, strava.isConnected, let syncDate = strava.lastStravaSync {
                    Text("Last Strava sync: \(Self.relativeSyncTime(syncDate))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                FooterView()
            }
            .padding(10)
        }
    }
}
