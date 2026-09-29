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
                MissedStravaDaysBanner()
                IdleView()
                FooterView()
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                MissedStravaDaysBanner()
                WaitingForTreadmillView()
                FooterView()
            }
        }
    }
}

/// The one "needs attention" pattern: recent days whose walks never reached Strava.
/// One day posts straight from the banner; several expand to a row per day.
struct MissedStravaDaysBanner: View {
    @ObservedObject private var strava = StravaService.shared
    @State private var expanded = false

    var body: some View {
        let days = strava.unsyncedDays
        if strava.isConnected && !days.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if days.count == 1 {
                    row(days[0], title: Self.sentence(for: days[0].date))
                } else {
                    HStack(spacing: 8) {
                        Text("\(days.count) days aren't on Strava")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer(minLength: 0)
                        Button(expanded ? "Hide" : "Show") { expanded.toggle() }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .tint(.orange)
                    }
                    if expanded {
                        ForEach(days) { day in
                            row(day, title: "\(Self.label(for: day.date)) · \(distanceTextFor(day.distance))")
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
        }
    }

    private func row(_ day: StravaService.UnsyncedDay, title: String) -> some View {
        let error = strava.dayPostErrors[day.key]
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.orange)
                if let error = error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
            if strava.postingDays.contains(day.key) {
                ProgressView().controlSize(.small)
            } else {
                Button(error == nil ? "Post" : "Retry") { post(day) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .tint(.orange)
                    .help("Post \(distanceTextFor(day.distance)) from \(day.sessionCount) walk\(day.sessionCount == 1 ? "" : "s") as one Strava activity")
            }
        }
    }

    private func post(_ day: StravaService.UnsyncedDay) {
        StravaService.shared.clearUploadResult()
        Task {
            _ = await StravaService.shared.postDay(day, notionService: NotionService.shared)
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.timeZone = NotionService.dayCalendar.timeZone
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        f.timeZone = NotionService.dayCalendar.timeZone
        return f
    }()

    private static func daysAgo(_ date: Date) -> Int {
        let calendar = NotionService.dayCalendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
    }

    /// "Yesterday", "Sunday" within the week, "Tue 22 Sep" once the weekday repeats.
    static func label(for date: Date) -> String {
        switch daysAgo(date) {
        case 1: return "Yesterday"
        case 2...6: return weekdayFormatter.string(from: date)
        default: return shortDateFormatter.string(from: date)
        }
    }

    static func sentence(for date: Date) -> String {
        daysAgo(date) <= 6
            ? "\(label(for: date))'s walks aren't on Strava"
            : "Walks from \(label(for: date)) aren't on Strava"
    }
}
