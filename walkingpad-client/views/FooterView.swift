import SwiftUI

/// Bottom bar with Stats and Quit buttons, pinned to the bottom of the popover.
struct FooterView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    @State private var showUploadConfirm: Bool = false

    /// Singleton reference to prevent duplicate stats windows.
    private static var statsWindow: NSWindow?

    private var stravaService: StravaService { StravaService.shared }
    private var notionService: NotionService { NotionService.shared }

    var body: some View {
        VStack(spacing: 4) {
            if showUploadConfirm {
                HStack(spacing: 6) {
                    Text("Upload to Strava?")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { showUploadConfirm = false }) {
                        Text("Cancel")
                            .font(.caption2.weight(.medium))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: .capsule)

                    Button(action: {
                        showUploadConfirm = false
                        postToStrava()
                    }) {
                        Text("Upload")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.1), in: .capsule)
                }
            }

            HStack(spacing: 6) {
                Button(action: { openStatsWindow() }) {
                    Label("Stats", systemImage: "chart.bar")
                        .font(.caption2.weight(.medium))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: .capsule)

                stravaButton

                Spacer()

                Button(action: {
                    walkingPadService.command()?.setSpeed(speed: 0)
                    workout.save()
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: .capsule)
            }
        }
    }

    @ViewBuilder
    private var stravaButton: some View {
        let strava = stravaService
        if strava.isSyncing {
            ProgressView()
                .controlSize(.mini)
                .padding(.horizontal, 6)
        } else if !strava.isConnected {
            Button(action: { strava.startOAuthFlow() }) {
                Image(systemName: "figure.run")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: .capsule)
            .help("Connect to Strava")
        } else if strava.isSyncedToday {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .help("Synced to Strava today")
        } else if strava.lastError != nil {
            Button(action: { showUploadConfirm = true; strava.clearUploadResult() }) {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: .capsule)
            .help(strava.lastError ?? "Error")
        } else {
            Button(action: { showUploadConfirm = true; strava.clearUploadResult() }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: .capsule)
            .help("Post today's walk to Strava")
        }
    }

    private func postToStrava() {
        let strava = stravaService
        let notion = notionService
        strava.clearUploadResult()
        Task {
            if let sessions = await notion.fetchTodaySessions(), !sessions.isEmpty {
                _ = await strava.postTodayActivity(sessions: sessions, notionService: notion)
            } else {
                await MainActor.run {
                    strava.uploadResultMessage = "No sessions found for today"
                    strava.uploadResultIsError = true
                }
            }
        }
    }

    private func openStatsWindow() {
        // Close existing window so we always show fresh data
        if let existing = FooterView.statsWindow {
            existing.close()
            FooterView.statsWindow = nil
        }

        let notion = notionService
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
            stravaService: stravaService
        )
        let hostingView = NSHostingView(rootView: statsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "WalkingPad Stats"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 400)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        FooterView.statsWindow = window

        // Fetch from Notion — only source of truth when configured
        if notionConfigured {
            Task {
                if let sessions = await notion.fetchAllSessions() {
                    let workouts = NotionService.groupSessionsByDate(sessions)
                    appLog("Stats: replacing with \(workouts.count) days from Notion (\(sessions.count) sessions)")
                    for w in workouts {
                        appLog("  Day: \(w.date), steps=\(w.steps), dist=\(w.distance), sessions=\(w.sessions?.count ?? 0)")
                    }
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

struct FooterView_Previews: PreviewProvider {
    static var previews: some View {
        FooterView()
    }
}
