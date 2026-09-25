import Foundation

// Replays treadmill frames through SessionTracker and checks the sessions it
// produces. There is no XCTest target in the Xcode project, so CI compiles this
// file together with SessionTracker.swift and runs it:
//
//   swiftc walkingpad-client/services/SessionTracker.swift \
//     Tests/SessionTrackerChecks/main.swift -o session-checks && ./session-checks

var failures = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

/// Drives a tracker with frames at explicit offsets (seconds) from t0.
struct Replay {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    var tracker = SessionTracker()
    var last: SessionTracker.Sample?
    var events: [SessionTracker.Event] = []

    mutating func frame(_ t: TimeInterval, speed: Int, steps: Int, distance: Int) {
        let sample = SessionTracker.Sample(time: t0.addingTimeInterval(t), speed: speed, steps: steps, distance: distance)
        if let last {
            events += tracker.ingest(previous: last, current: sample)
        }
        last = sample
    }

    mutating func tick(_ t: TimeInterval) {
        events += tracker.tick(now: t0.addingTimeInterval(t))
    }

    mutating func stop(_ t: TimeInterval) {
        tracker.requestStop(at: t0.addingTimeInterval(t))
    }

    var sessions: [SessionTracker.Session] {
        events.compactMap { if case .ended(let s) = $0 { return s } else { return nil } }
    }
}

// 1. The reported bug: a speed change produces a burst of frames 1 s apart while
//    the step counter stalls. The old detector ended the session here.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 100, distance: 1000)
    r.frame(5, speed: 30, steps: 100, distance: 1000)      // belt starts
    r.frame(10, speed: 30, steps: 108, distance: 1010)
    r.frame(15, speed: 30, steps: 118, distance: 1020)
    r.frame(16, speed: 40, steps: 118, distance: 1020)     // speed change reply
    r.frame(17, speed: 40, steps: 118, distance: 1020)     // another quick reply
    r.frame(18, speed: 40, steps: 118, distance: 1021)
    r.frame(23, speed: 40, steps: 130, distance: 1035)
    check(r.tracker.isActive, "a speed change must not end the session")
    check(r.sessions.isEmpty, "no session should have ended during a speed change")
    check(r.tracker.phase == .walking, "still walking after the speed change, got \(r.tracker.phase)")
}

// 2. A single speed-0 frame is only a pause; steps resuming continue the same session.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 0, distance: 0)
    r.frame(5, speed: 35, steps: 0, distance: 0)
    r.frame(10, speed: 35, steps: 10, distance: 15)
    r.frame(15, speed: 0, steps: 10, distance: 15)          // glitch / brief stop
    check(r.tracker.phase == .paused, "speed 0 pauses, got \(r.tracker.phase)")
    r.frame(20, speed: 35, steps: 20, distance: 30)
    check(r.tracker.phase == .walking, "steps resume the session, got \(r.tracker.phase)")
    check(r.events.contains(.resumed), "a resumed event is emitted")
    check(r.sessions.isEmpty, "the pause did not end the session")
}

// 3. Stepping off for under 60 s keeps one session; the total is preserved.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 0, distance: 0)
    r.frame(5, speed: 35, steps: 0, distance: 0)
    r.frame(10, speed: 35, steps: 10, distance: 15)
    for t in stride(from: 15.0, through: 60.0, by: 5.0) {    // 50 s without steps
        r.frame(t, speed: 35, steps: 10, distance: 15)
    }
    r.frame(65, speed: 35, steps: 20, distance: 30)
    check(r.sessions.isEmpty, "a 55 s pause stays one session")
    check(r.tracker.steps == 20, "steps accumulate across the pause, got \(r.tracker.steps)")
}

// 4. 60 s without steps ends the session, dated to the last step.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 0, distance: 0)
    r.frame(5, speed: 35, steps: 0, distance: 0)
    r.frame(10, speed: 35, steps: 10, distance: 15)
    r.frame(15, speed: 35, steps: 25, distance: 40)
    for t in stride(from: 20.0, through: 80.0, by: 5.0) {
        r.frame(t, speed: 35, steps: 25, distance: 40)
    }
    check(r.sessions.count == 1, "one session after 60 s idle, got \(r.sessions.count)")
    if let s = r.sessions.first {
        check(s.steps == 25 && s.distance == 40, "session totals \(s.steps)/\(s.distance)")
        check(s.end == r.t0.addingTimeInterval(15), "ends at the last step, got \(s.end.timeIntervalSince(r.t0))")
        check(s.start == r.t0.addingTimeInterval(5), "starts when the belt started")
    }
    check(!r.tracker.isActive, "tracker is idle afterwards")
}

// 5. Silence (no frames at all) still ends the session via tick.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 0, distance: 0)
    r.frame(5, speed: 35, steps: 12, distance: 20)
    r.tick(30)
    check(r.tracker.phase == .paused, "quiet for 25 s → paused")
    r.tick(66)
    check(r.sessions.count == 1, "quiet for 61 s → ended")
}

// 6. Tapping Stop ends promptly once the belt confirms with speed 0.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 0, distance: 0)
    r.frame(5, speed: 35, steps: 0, distance: 0)
    r.frame(10, speed: 35, steps: 30, distance: 50)
    r.stop(11)
    r.frame(12, speed: 20, steps: 33, distance: 54)          // decelerating
    check(r.tracker.phase == .stopping, "still stopping while the belt slows")
    r.frame(13, speed: 0, steps: 34, distance: 55)
    check(r.sessions.count == 1, "stop + speed 0 ends the session")
    check(r.sessions.first?.steps == 34, "steps while decelerating are kept")
}

// 7. Tapping Stop on a treadmill that never reports speed 0 ends after 5 quiet seconds.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 0, distance: 0)
    r.frame(5, speed: 35, steps: 30, distance: 50)
    r.stop(6)
    r.frame(8, speed: 35, steps: 30, distance: 50)
    check(r.sessions.isEmpty, "not yet: only 2 s since stop")
    r.frame(12, speed: 35, steps: 30, distance: 50)
    check(r.sessions.count == 1, "5 s without steps after Stop ends it")
}

// 8. A belt run with nobody on it is discarded, not recorded.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 0, distance: 0)
    r.frame(5, speed: 20, steps: 0, distance: 10)
    r.tick(70)
    check(r.sessions.isEmpty, "no steps → no session")
    check(r.events.contains(.discarded), "the empty run is reported as discarded")
}

// 9. Connecting mid-walk starts a session from the frame before the first steps.
do {
    var r = Replay()
    r.frame(0, speed: 35, steps: 500, distance: 700)
    r.frame(5, speed: 35, steps: 510, distance: 715)
    check(r.tracker.isActive, "steps flowing start a session")
    check(r.tracker.start == r.t0, "start is the previous frame")
    check(r.tracker.steps == 10, "only the diff counts, got \(r.tracker.steps)")
}

// 10. A counter reset doesn't produce negative totals.
do {
    var r = Replay()
    r.frame(0, speed: 0, steps: 0, distance: 0)
    r.frame(5, speed: 35, steps: 40, distance: 60)
    r.frame(10, speed: 35, steps: 2, distance: 3)             // reset
    check(r.tracker.steps == 40, "reset frame ignored, got \(r.tracker.steps)")
}

if failures == 0 {
    print("SessionTracker checks passed")
} else {
    print("\(failures) SessionTracker check(s) failed")
    exit(1)
}
