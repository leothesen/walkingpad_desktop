import SwiftUI
import AppKit

/// Posts today's walks to Strava as one activity. Used by "Done for today" and the
/// footer's "Post to Strava" chip. Progress lands in `workout.finishDayState`.
enum StravaDayPoster {
    static func postToday(workout: Workout) {
        let notion = NotionService.shared
        let strava = StravaService.shared
        strava.clearUploadResult()
        workout.finishDayState = .posting

        Task {
            // In-memory sessions always include the one that just ended; Notion adds
            // any from before an app restart.
            let local = await MainActor.run { workout.todaySessions }
            let remote = await notion.fetchTodaySessions() ?? []
            let sessions = mergeSessions(local: local, remote: remote)

            let success: Bool
            if sessions.isEmpty {
                ActivityLog.shared.error("No sessions found for today")
                success = false
            } else {
                success = await strava.postTodayActivity(sessions: sessions, notionService: notion)
            }
            ActivityLog.shared.info("Done for today: \(success ? "posted" : "failed")")
            await MainActor.run {
                workout.finishDayState = success ? .posted : .failed
            }
        }
    }

    /// Merges local in-memory sessions with Notion sessions, deduplicating by start time.
    static func mergeSessions(local: [SessionSaveData], remote: [SessionSaveData]) -> [SessionSaveData] {
        if local.isEmpty { return remote }
        if remote.isEmpty { return local }

        var merged = local
        for remoteSession in remote {
            let isDuplicate = local.contains { abs($0.startTime.timeIntervalSince(remoteSession.startTime)) < 60 }
            if !isDuplicate {
                merged.append(remoteSession)
            }
        }
        return merged.sorted { $0.startTime < $1.startTime }
    }
}

/// Bottom row of the idle states: Stats, and Strava only when there's something to do.
/// Updates and Quit live in the native menu items below the popover.
struct FooterView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout
    @ObservedObject private var strava = StravaService.shared

    /// First tap arms the post, second tap sends it — a Strava activity is public.
    @State private var confirmPost = false

    /// Singleton reference to prevent duplicate stats windows.
    private static var statsWindow: NSWindow?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { FooterView.openStatsWindow(workout: workout, walkingPadService: walkingPadService) }) {
                Label("Stats", systemImage: "chart.bar.xaxis")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.glass)

            stravaChip

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var stravaChip: some View {
        if !strava.isConnected {
            Button("Connect Strava") { strava.startOAuthFlow() }
                .buttonStyle(.glass)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if strava.isSyncing || workout.finishDayState == .posting {
            ProgressView().controlSize(.small).padding(.horizontal, 6)
        } else if !strava.isSyncedToday && !workout.todaySessions.isEmpty {
            Button {
                if confirmPost {
                    confirmPost = false
                    StravaDayPoster.postToday(workout: workout)
                } else {
                    confirmPost = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { confirmPost = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(strava.lastError == nil ? Color.orange : Color.red).frame(width: 6, height: 6)
                    Text(confirmPost ? "Post \(distanceTextFor(workout.todayDistance))?" : (strava.lastError == nil ? "Post to Strava" : "Retry Strava"))
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.glass)
            .tint(.orange)
            .help(strava.lastError ?? "Post today's walks to Strava as one activity")
        }
    }

    // MARK: - Stats window

    static func openStatsWindow(workout: Workout, walkingPadService: WalkingPadService) {
        // Close existing window so we always show fresh data
        if let existing = statsWindow {
            existing.close()
            statsWindow = nil
        }

        let notion = NotionService.shared
        let notionConfigured = notion.isConfigured

        // If Notion is configured, start empty and load from Notion only.
        // Otherwise fall back to local data.
        let initialWorkouts = notionConfigured ? [] : workout.loadAll()
        let viewModel = StatsViewModel(workouts: initialWorkouts)
        if notionConfigured { viewModel.isLoading = true }

        let statsView = StatsWindowView(
            viewModel: viewModel,
            walkingPadService: walkingPadService,
            notionService: notion,
            stravaService: StravaService.shared
        )
        .environmentObject(GoalSettings.shared)
        .environmentObject(workout)

        let hostingView = NSHostingView(rootView: statsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Behind-window blur, so the desktop shows through the window like the
        // system's own glass surfaces. Follows the system appearance.
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 820),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "WalkingPad Stats"
        window.isMovableByWindowBackground = true
        window.contentView = background
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 720)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        statsWindow = window

        // Fetch from Notion — only source of truth when configured
        if notionConfigured {
            Task {
                if let sessions = await notion.fetchAllSessions() {
                    let workouts = NotionService.groupSessionsByDate(sessions)
                    appLog("Stats: replacing with \(workouts.count) days from Notion (\(sessions.count) sessions)")
                    await MainActor.run {
                        viewModel.replaceWorkouts(workouts, source: "Notion")
                    }
                } else {
                    // Notion unreachable — fall back to local as emergency
                    let localWorkouts = workout.loadAll()
                    await MainActor.run {
                        viewModel.replaceWorkouts(localWorkouts, source: "local (Notion unavailable)")
                    }
                }
            }
        }
    }
}
