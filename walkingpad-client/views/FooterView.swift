import SwiftUI

/// Bottom bar with Stats and Quit buttons, pinned to the bottom of the popover.
/// Warning: Quit uses exit(0) which bypasses cleanup — see KNOWN_ISSUES.md #8.
struct FooterView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    /// Singleton reference to prevent duplicate stats windows.
    private static var statsWindow: NSWindow?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { openStatsWindow() }) {
                Label("Stats", systemImage: "chart.bar")
                    .font(.caption2.weight(.medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            Button(action: {
                walkingPadService.command()?.setSpeed(speed: 0)
                workout.save()
                exit(0)
            }) {
                Text("Quit")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func openStatsWindow() {
        // Close existing window so we always show fresh data
        if let existing = FooterView.statsWindow {
            existing.close()
            FooterView.statsWindow = nil
        }

        let viewModel = StatsViewModel(workouts: workout.loadAll())
        let statsView = StatsWindowView(viewModel: viewModel, walkingPadService: walkingPadService)
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
