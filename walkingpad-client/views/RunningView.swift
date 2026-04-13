import SwiftUI
import CoreBluetooth

/// Displayed when the treadmill is running (speed > 0).
struct RunningView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout

    @State private var sliderSpeed: Double = 0
    @State private var isDragging: Bool = false
    @State private var showFinishConfirm: Bool = false

    var body: some View {
        let state = walkingPadService.lastStatus()
        let currentSpeed = Double(state?.speed ?? 0) / 10.0

        VStack(spacing: 6) {
            WorkoutStateView()

            // Speed control
            VStack(spacing: 0) {
                Text(String(format: "%.1f", sliderSpeed))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                Text("km/h")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 6) {
                    Button(action: { nudgeSpeed(-0.1) }) {
                        Image(systemName: "minus")
                            .font(.caption2.weight(.semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)

                    Slider(value: $sliderSpeed, in: 0.5...8.0, step: 0.5) {
                        SwiftUI.EmptyView()
                    } onEditingChanged: { editing in
                        isDragging = editing
                        if !editing {
                            walkingPadService.command()?.setSpeed(speed: UInt8(sliderSpeed * 10))
                        }
                    }

                    Button(action: { nudgeSpeed(0.1) }) {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            // Mode + Stop row
            HStack(spacing: 6) {
                if state?.walkingMode != nil {
                    modeButton(.manual, current: state?.walkingMode)
                    modeButton(.automatic, current: state?.walkingMode)
                }
            }

            Button(action: {
                walkingPadService.command()?.setSpeed(speed: 0)
            }) {
                Text("Stop")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(.red.opacity(0.1)).interactive(), in: .capsule)

            if showFinishConfirm {
                HStack(spacing: 6) {
                    Text("Post to Strava?")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { showFinishConfirm = false }) {
                        Text("No")
                            .font(.caption2.weight(.medium))
                            .frame(width: 40)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Button(action: {
                        showFinishConfirm = false
                        stopAndFinishDay()
                    }) {
                        Text("Yes")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .frame(width: 40)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(.orange.opacity(0.1)).interactive(), in: .capsule)
                }
            } else {
                Button(action: { showFinishConfirm = true }) {
                    Text("Stop & Finish Day")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .glassEffect(.regular.tint(.orange.opacity(0.1)).interactive(), in: .capsule)
            }
        }
        .onAppear { sliderSpeed = max(currentSpeed, 0.5) }
        .onChange(of: state?.speed) { _, newSpeed in
            guard !isDragging else { return }
            let reported = Double(newSpeed ?? 0) / 10.0
            if reported > 0 && abs(reported - sliderSpeed) > 0.05 {
                sliderSpeed = reported
            }
        }
    }

    private func stopAndFinishDay() {
        walkingPadService.command()?.setSpeed(speed: 0)

        let notion = NotionService.shared
        let strava = StravaService.shared

        ActivityLog.shared.progress("Stopping treadmill, waiting for session to finalize…")
        Task {
            // Poll until the current session ends (idle detection sets currentSessionStart to nil)
            let deadline = Date().addingTimeInterval(30)
            while await MainActor.run(body: { workout.currentSessionStart }) != nil {
                if Date() > deadline {
                    ActivityLog.shared.error("Timeout waiting for session to finalize")
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }

            // Use in-memory sessions as primary source — always has the just-completed session
            let localSessions = await MainActor.run { workout.todaySessions }

            // Also fetch from Notion to capture sessions from before an app restart
            let notionSessions = await notion.fetchTodaySessions() ?? []

            // Merge both sources, deduplicating by start time
            let sessions = mergeSessions(local: localSessions, remote: notionSessions)

            if !sessions.isEmpty {
                let success = await strava.postTodayActivity(sessions: sessions, notionService: notion)
                ActivityLog.shared.info("Stop & Finish Day: \(success ? "completed" : "failed")")
            } else {
                ActivityLog.shared.error("No sessions found for today")
            }
        }
    }

    /// Merges local in-memory sessions with Notion sessions, deduplicating by start time.
    private func mergeSessions(local: [SessionSaveData], remote: [SessionSaveData]) -> [SessionSaveData] {
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

    private func nudgeSpeed(_ delta: Double) {
        let newSpeed = min(max(sliderSpeed + delta, 0.5), 8.0)
        // Round to nearest 0.1 to avoid floating point drift
        sliderSpeed = (newSpeed * 10).rounded() / 10
        walkingPadService.command()?.setSpeed(speed: UInt8(sliderSpeed * 10))
    }

    private func modeButton(_ mode: WalkingMode, current: WalkingMode?) -> some View {
        Button(action: { walkingPadService.command()?.setWalkingMode(mode: mode) }) {
            Text(mode == .manual ? "Manual" : "Auto")
                .font(.caption2.weight(.medium))
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .glassEffect(
            mode == current ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .capsule
        )
    }
}
