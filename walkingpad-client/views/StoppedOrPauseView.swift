import SwiftUI
import CoreBluetooth

/// Starts the belt and tracks the attempt, shared by the idle state's Start button
/// and the "Walk again" button after a session ends.
final class TreadmillStarter: ObservableObject {
    static let shared = TreadmillStarter()

    @Published private(set) var isStarting = false
    @Published private(set) var timedOut = false
    private var attempt = 0

    /// Speed (tenths of km/h) to bring the belt to once it reports movement. Cleared
    /// when the belt reports it, when the user picks a speed or stops, or on timeout.
    private var pendingSpeed: UInt8? = nil
    private var pendingSpeedDeadline: Date = .distantPast
    private var lastSpeedCommand: Date = .distantPast

    /// Sends wake+start, then polls more eagerly than the regular 5 s timer so the
    /// UI flips to the walking state as soon as the belt reports movement. The
    /// speed is set from the status frames (`statusReceived`), not on a timer: the
    /// treadmill counts down before the belt moves, so a fixed delay can miss it.
    /// Gives up after 15 s.
    func start(service: WalkingPadService, speedKmh: Double) {
        isStarting = true
        timedOut = false
        attempt += 1
        let current = attempt
        pendingSpeed = UInt8((speedKmh * 10).rounded())
        pendingSpeedDeadline = Date().addingTimeInterval(25)
        lastSpeedCommand = .distantPast

        service.command()?.wakeAndStart()

        // wakeAndStart waits 1.5 s before starting the belt; poll through the countdown.
        for delay in [2.0, 3.0, 4.0, 5.0, 6.0, 7.5, 9.0, 11.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.attempt == current, self.isStarting || self.pendingSpeed != nil else { return }
                service.command()?.updateStatus()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            guard self.isStarting, self.attempt == current else { return }
            self.isStarting = false
            self.timedOut = true
            self.pendingSpeed = nil
        }
    }

    /// Called for every live status frame. Once the belt is moving, asks for the
    /// chosen speed and keeps asking (at most every 1.5 s) until the belt reports it.
    func statusReceived(_ state: DeviceState, service: WalkingPadService) {
        guard let target = pendingSpeed, state.speed > 0 else { return }
        if Date() > pendingSpeedDeadline {
            appLog("Start speed: gave up waiting for \(Double(target) / 10) km/h (belt at \(state.speedKmh()))", type: .error)
            pendingSpeed = nil
            return
        }
        if state.speed == Int(target) {
            appLog("Start speed: belt at \(state.speedKmh()) km/h")
            pendingSpeed = nil
            return
        }
        // The belt answers each command with a status frame, so without this
        // throttle every reply would trigger another command.
        guard Date().timeIntervalSince(lastSpeedCommand) >= 1.5 else { return }
        lastSpeedCommand = Date()
        appLog("Start speed: belt at \(state.speedKmh()) km/h, setting \(Double(target) / 10)")
        service.command()?.setSpeed(speed: target)
    }

    /// The user chose a speed or stopped; don't override them with the start speed.
    func cancelPendingSpeed() {
        pendingSpeed = nil
    }

    /// The belt is running; the start attempt is over.
    func beltIsRunning() {
        if isStarting { isStarting = false }
        if timedOut { timedOut = false }
    }
}

/// Idle state: how the day is going, and the Start button.
struct IdleView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout
    @EnvironmentObject var goal: GoalSettings
    @ObservedObject private var starter = TreadmillStarter.shared

    /// The speed the belt is brought to after starting. Persisted.
    @AppStorage("startSpeedKmh") private var startSpeed: Double = 3.5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodayGoalHeader(estimateSpeedKmh: startSpeed)

            TodayStatsRow()

            HStack(spacing: 6) {
                if starter.isStarting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Starting treadmill")
                            .font(.callout.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .glassEffect(.regular.tint(.green.opacity(0.25)), in: .capsule)
                } else {
                    Button {
                        starter.start(service: walkingPadService, speedKmh: startSpeed)
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                    .controlSize(.large)
                }

                Button(action: cycleStartSpeed) {
                    HStack(spacing: 3) {
                        Text(String(format: "%.1f", startSpeed))
                            .monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout.weight(.semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help("Starting speed in km/h — click to change")
                .accessibilityLabel("Starting speed \(String(format: "%.1f", startSpeed)) kilometres per hour")
            }

            if starter.timedOut {
                Text("Treadmill didn't respond — try again")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Steps through the presets; an off-preset value snaps to the first.
    private func cycleStartSpeed() {
        let speeds = SpeedPresets.all.map(\.kmh)
        if let index = speeds.firstIndex(where: { abs($0 - startSpeed) < 0.05 }) {
            startSpeed = speeds[(index + 1) % speeds.count]
        } else {
            startSpeed = speeds[0]
        }
    }
}
