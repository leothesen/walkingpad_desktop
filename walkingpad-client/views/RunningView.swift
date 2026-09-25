import SwiftUI
import CoreBluetooth

/// Walking state: this session's time and distance, the speed control, and a thin
/// bar for the day. No Strava or stats here — nothing you need mid-walk.
struct WalkingView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout
    @EnvironmentObject var goal: GoalSettings

    @State private var targetSpeed: Double = 0

    var body: some View {
        let state = walkingPadService.lastStatus()
        let reportedSpeed = Double(state?.speed ?? 0) / 10.0

        VStack(alignment: .leading, spacing: 12) {
            sessionHeader

            speedControl

            presetRow(mode: state?.walkingMode)

            dayProgress

            stopButton
        }
        .onAppear {
            targetSpeed = reportedSpeed > 0 ? reportedSpeed : 3.5
            TreadmillStarter.shared.beltIsRunning()
        }
        .onChange(of: state?.speed) { _, newSpeed in
            let reported = Double(newSpeed ?? 0) / 10.0
            if reported > 0 && abs(reported - targetSpeed) > 0.05 {
                targetSpeed = reported
            }
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = workout.currentSessionStartTime.map { Int(timeline.date.timeIntervalSince($0)) } ?? 0

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    phaseLabel(now: timeline.date)
                    Text(timerText(elapsed))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(distanceTextFor(workout.sessionDistance))
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Text("\(workout.sessionSteps.formatted()) steps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func phaseLabel(now: Date) -> some View {
        switch workout.sessionPhase {
        case .paused:
            let remaining = workout.pauseDeadline.map { max(0, Int($0.timeIntervalSince(now).rounded())) } ?? 0
            statusDot(color: .orange, text: "Paused · ends in \(remaining)s")
        case .stopping:
            statusDot(color: .red, text: "Stopping…")
        default:
            statusDot(color: .green, text: workout.currentSessionStartTime == nil ? "Belt running" : "Walking")
        }
    }

    private func statusDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .background(Circle().fill(color.opacity(0.25)).frame(width: 13, height: 13))
            Text(text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK: - Speed

    private var speedControl: some View {
        HStack(spacing: 6) {
            Button { nudgeSpeed(-SpeedPresets.step) } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel("Slower")

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", targetSpeed))
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                Text("km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button { nudgeSpeed(SpeedPresets.step) } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel("Faster")
        }
        .padding(5)
        .glassEffect(.regular, in: .capsule)
        .disabled(workout.sessionPhase == .stopping)
    }

    private func presetRow(mode: WalkingMode?) -> some View {
        HStack(spacing: 4) {
            ForEach(SpeedPresets.all, id: \.kmh) { preset in
                let isCurrent = abs(targetSpeed - preset.kmh) < 0.05
                Button { setSpeed(preset.kmh) } label: {
                    Text(preset.label)
                        .font(.caption.weight(isCurrent ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(isCurrent ? .green : nil)
                .help(String(format: "%.1f km/h", preset.kmh))
            }

            if let mode {
                let isAuto = mode == .automatic
                Button {
                    walkingPadService.command()?.setWalkingMode(mode: isAuto ? .manual : .automatic)
                } label: {
                    Text("Auto")
                        .font(.caption.weight(isAuto ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(isAuto ? .green : nil)
                .help("Automatic mode: the belt follows where you stand")
            }
        }
        .disabled(workout.sessionPhase == .stopping)
    }

    // MARK: - Day

    private var dayProgress: some View {
        let dayDistance = workout.todayDistance
        let progress = goal.progress(distanceMeters: dayDistance, steps: workout.steps, seconds: workout.walkingSeconds)
        let sessionSeconds = workout.currentSessionStartTime.map { Int(Date().timeIntervalSince($0)) } ?? 0
        let live = goal.progress(distanceMeters: workout.sessionDistance, steps: workout.sessionSteps, seconds: sessionSeconds)
        let eta = goal.timeToGoal(distanceMeters: dayDistance, steps: workout.steps, seconds: workout.walkingSeconds, speedKmh: targetSpeed)

        return VStack(alignment: .leading, spacing: 6) {
            GoalProgressBar(fraction: progress, liveFraction: live)
            HStack {
                Text(dayAmountText + " today")
                Spacer(minLength: 0)
                if progress >= 1 {
                    Text("Goal reached")
                        .foregroundStyle(.green)
                } else if let eta {
                    Text("goal in \(compactDuration(eta))")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var dayAmountText: String {
        let amount = goal.amount(distanceMeters: workout.todayDistance, steps: workout.steps, seconds: workout.walkingSeconds)
        switch goal.kind {
        case .distance: return String(format: "%.2f / %@", amount, goal.label)
        case .steps: return "\(Int(amount).formatted()) / \(goal.label)"
        case .time: return "\(Int(amount)) / \(goal.label)"
        }
    }

    // MARK: - Stop

    @ViewBuilder
    private var stopButton: some View {
        if workout.sessionPhase == .stopping {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Finishing session…")
                    .font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .glassEffect(.regular.tint(.red.opacity(0.2)), in: .capsule)
        } else {
            Button(role: .destructive, action: stopTreadmill) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    /// Sends the stop command and polls eagerly so the belt's speed 0 is seen
    /// quickly. The session ends once the belt confirms (see SessionTracker).
    private func stopTreadmill() {
        workout.requestStop()
        walkingPadService.command()?.setSpeed(speed: 0)
        for delay in [1.0, 2.5, 4.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                walkingPadService.command()?.updateStatus()
            }
        }
    }

    /// Moves one step up or down. An off-step speed (e.g. 3.2 set on the treadmill's
    /// remote) snaps to the next step in that direction — 3.5 up, 3.0 down.
    private func nudgeSpeed(_ delta: Double) {
        let steps = targetSpeed / SpeedPresets.step
        // Tolerance absorbs floating point noise so an on-step speed moves a full step
        let target = delta > 0 ? (steps + 0.01).rounded(.up) : (steps - 0.01).rounded(.down)
        setSpeed(target * SpeedPresets.step)
    }

    private func setSpeed(_ kmh: Double) {
        let clamped = min(max(kmh, SpeedPresets.minKmh), SpeedPresets.maxKmh)
        // Round to nearest 0.1 to avoid floating point drift
        targetSpeed = (clamped * 10).rounded() / 10
        walkingPadService.command()?.setSpeed(speed: UInt8((targetSpeed * 10).rounded()))
    }
}

/// Shown after a session ends, until the popover has been seen: what was saved,
/// and the one decision that matters now — keep going or call it a day.
struct SessionEndedView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout
    @EnvironmentObject var goal: GoalSettings
    @ObservedObject private var strava = StravaService.shared
    @AppStorage("startSpeedKmh") private var startSpeed: Double = 3.5

    let session: SessionSaveData

    var body: some View {
        let progress = goal.progress(distanceMeters: workout.todayDistance, steps: workout.steps, seconds: workout.walkingSeconds)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.green))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Session saved")
                        .font(.headline)
                    Text("\(distanceTextFor(session.distance)) · \(compactDuration(session.endTime.timeIntervalSince(session.startTime))) · \(session.steps.formatted()) steps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                GoalProgressBar(fraction: progress)
                Text(progress >= 1 ? "Goal reached · \(distanceTextFor(workout.todayDistance)) today" : "\(distanceTextFor(workout.todayDistance)) today of \(goal.label)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Button {
                    workout.dismissRecentSession()
                    TreadmillStarter.shared.start(service: walkingPadService, speedKmh: startSpeed)
                } label: {
                    Text("Walk again")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(!walkingPadService.isConnected())

                if showsFinishDay {
                    finishDayButton
                }
            }

            finishDayCaption
        }
    }

    private var showsFinishDay: Bool {
        strava.isConnected && (!strava.isSyncedToday || workout.finishDayState != .none)
    }

    @ViewBuilder
    private var finishDayButton: some View {
        switch workout.finishDayState {
        case .posting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Posting…").font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .capsule)
        case .posted:
            Label("Posted", systemImage: "checkmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, minHeight: 36)
                .glassEffect(.regular, in: .capsule)
        case .none, .failed:
            Button {
                StravaDayPoster.postToday(workout: workout)
            } label: {
                Text(workout.finishDayState == .failed ? "Retry post" : "Done for today")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.orange)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var finishDayCaption: some View {
        if workout.finishDayState == .failed {
            Text(strava.lastError ?? "Couldn't post to Strava")
                .font(.caption)
                .foregroundStyle(.red)
        } else if workout.finishDayState == .posted {
            Text("Today's walks are on Strava")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if showsFinishDay {
            let count = workout.todaySessions.count
            Text("“Done for today” posts \(count == 1 ? "today's walk" : "all \(count) walks") to Strava")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
