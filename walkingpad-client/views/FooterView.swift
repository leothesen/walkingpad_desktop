import SwiftUI

/// Bottom bar with Stats, Login/Logout, and Quit buttons.
/// Warning: Quit uses exit(0) which bypasses cleanup — see KNOWN_ISSUES.md #8.
struct FooterView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    /// Singleton reference to prevent duplicate stats windows.
    private static var statsWindow: NSWindow?

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: { openStatsWindow() }) {
                Text("Stats")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: .capsule)

            LoginLogoutButton()

            Button(action: {
                walkingPadService.command()?.setSpeed(speed: 0)
                workout.save()
                exit(0)
            }) {
                Text("Quit")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func openStatsWindow() {
        // Bring existing window to front if already open
        if let existing = FooterView.statsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let viewModel = StatsViewModel(workouts: workout.loadAll())
        let statsView = StatsWindowView(viewModel: viewModel)
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

        FooterView.statsWindow = window
    }
}

struct FooterView_Previews: PreviewProvider {
    static var previews: some View {
        FooterView()
    }
}
