import Foundation

/// Decides when a walking session starts, pauses and ends, from the treadmill's
/// live status frames.
///
/// Every rule is measured in wall-clock time, never in a number of frames. The
/// WalkingPad sends frames irregularly: the 5 s poll, plus an extra reply after
/// most commands. The previous detector ended a session after "two frames without
/// new steps", which could mean ten seconds or one. After a speed change the belt
/// re-accelerates, the step counter stalls for a moment and a couple of quick
/// frames arrive, so a walk would end mid-stride and restart as a second session.
///
/// Rules:
/// - A session starts when the belt starts moving (speed 0 → >0), or when steps
///   flow while no session is active (the app connected mid-walk).
/// - No new steps for `pauseAfter` seconds, or a speed-0 frame → paused.
///   Steps resume → the same session carries on.
/// - No new steps for `endAfter` seconds → ended. The end time is the last step,
///   so the pause itself isn't counted.
/// - After the user taps Stop, the session ends as soon as the belt reports
///   speed 0 or produces no steps for `stopConfirmAfter` seconds.
/// - A session that never produced a step is discarded (belt ran, nobody walked).
///
/// Pure value type with no UI or BLE dependencies, so it can be exercised by
/// replaying frames (see `Tests/SessionTrackerChecks`).
struct SessionTracker {
    struct Config {
        var pauseAfter: TimeInterval = 10
        var endAfter: TimeInterval = 60
        var stopConfirmAfter: TimeInterval = 5
    }

    /// The fields of a live status frame the tracker cares about.
    struct Sample: Equatable {
        var time: Date
        /// Tenths of km/h, as reported by the treadmill.
        var speed: Int
        var steps: Int
        /// Meters.
        var distance: Int
    }

    struct Session: Equatable {
        var start: Date
        var end: Date
        var steps: Int
        /// Meters.
        var distance: Int
    }

    enum Phase: Equatable {
        case idle
        case walking
        case paused
        /// The user tapped Stop; waiting for the belt to confirm.
        case stopping
    }

    enum Event: Equatable {
        case started(Date)
        case paused
        case resumed
        case ended(Session)
        /// A session ended without a single step and was dropped.
        case discarded
    }

    let config: Config
    private(set) var phase: Phase = .idle
    private(set) var start: Date?
    private(set) var steps = 0
    private(set) var distance = 0
    /// When the step counter last moved in this session (its start, before the first step).
    private(set) var lastActivity: Date?
    private var stopRequestedAt: Date?

    init(config: Config = Config()) {
        self.config = config
    }

    var isActive: Bool { start != nil }

    /// When a paused session will end if no steps arrive, or nil when not paused.
    var pauseDeadline: Date? {
        guard phase == .paused, let last = lastActivity else { return nil }
        return last.addingTimeInterval(config.endAfter)
    }

    /// The user asked the belt to stop. The session ends once the belt confirms.
    mutating func requestStop(at time: Date) {
        guard isActive else { return }
        stopRequestedAt = time
        phase = .stopping
    }

    /// Folds one live frame into the session, given the frame before it.
    mutating func ingest(previous: Sample, current: Sample) -> [Event] {
        let stepDiff = current.steps - previous.steps
        let distanceDiff = current.distance - previous.distance

        // Counters only go backwards when the treadmill resets them (power cycle).
        // There's no diff to learn from that frame, but time still passes.
        guard stepDiff >= 0, distanceDiff >= 0 else {
            return evaluate(now: current.time, speed: current.speed)
        }

        var events: [Event] = []

        if start == nil {
            let beltStarted = previous.speed == 0 && current.speed > 0
            guard beltStarted || stepDiff > 0 else { return [] }
            // Steps already flowing means the walking began before this frame.
            let startTime = beltStarted ? current.time : previous.time
            start = startTime
            lastActivity = startTime
            steps = 0
            distance = 0
            stopRequestedAt = nil
            phase = .walking
            events.append(.started(startTime))
        }

        steps += stepDiff
        distance += distanceDiff

        if stepDiff > 0 {
            lastActivity = current.time
            if phase == .paused {
                phase = .walking
                events.append(.resumed)
            }
        }

        return events + evaluate(now: current.time, speed: current.speed)
    }

    /// Advances time without a frame, so a session still ends when the treadmill
    /// goes quiet (switched off, out of range, Mac asleep).
    mutating func tick(now: Date) -> [Event] {
        evaluate(now: now, speed: nil)
    }

    /// Ends the active session immediately (day rollover, app quit).
    mutating func finishNow() -> Event? {
        guard isActive else { return nil }
        return finish()
    }

    private mutating func evaluate(now: Date, speed: Int?) -> [Event] {
        guard isActive, let last = lastActivity else { return [] }
        let quiet = now.timeIntervalSince(last)

        if phase == .stopping, let requested = stopRequestedAt {
            let quietSinceRequest = now.timeIntervalSince(max(last, requested))
            if speed == 0 || quietSinceRequest >= config.stopConfirmAfter || quiet >= config.endAfter {
                return [finish()]
            }
            return []
        }

        if quiet >= config.endAfter {
            return [finish()]
        }

        if phase == .walking && (quiet >= config.pauseAfter || speed == 0) {
            phase = .paused
            return [.paused]
        }

        return []
    }

    private mutating func finish() -> Event {
        let session = Session(start: start ?? Date(), end: lastActivity ?? Date(), steps: steps, distance: distance)
        phase = .idle
        start = nil
        lastActivity = nil
        stopRequestedAt = nil
        steps = 0
        distance = 0
        return session.steps > 0 ? .ended(session) : .discarded
    }
}
