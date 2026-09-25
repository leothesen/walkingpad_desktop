import SwiftUI
import Foundation
import UserNotifications

/// Snapshot of the current workout counters, used for MQTT publishing.
struct WorkoutState {
    var steps: Int
    var distance: Int
    var walkingSeconds: Int
}

/// Accumulates daily step/distance/time totals from treadmill state updates.
///
/// This is the central data model for the UI — its `@Published` properties drive
/// SwiftUI re-renders via `@EnvironmentObject`. Data is persisted to `workouts.json`
/// and reloaded on launch.
///
/// Key behaviors:
/// - Computes diffs between consecutive BLE state updates to accumulate counters
/// - Guards against negative diffs (treadmill counter reset) and reconnection bursts
/// - Delegates session start/pause/end decisions to `SessionTracker` (time-based)
/// - Resets daily counters at midnight (checked every polling interval)
/// - Saves on speed changes and at least once a minute while walking
class Workout: ObservableObject {
    @Published
    public var steps: Int = 0

    @Published
    public var distance: Int = 0

    @Published
    public var walkingSeconds: Int = 0

    /// Sessions completed today (persisted to workouts.json).
    @Published
    public var todaySessions: [SessionSaveData] = []

    public var lastUpdateTime: Date = Date()

    /// Decides session boundaries. Mutated only on the main thread (BLE callbacks
    /// and timers both run there).
    private var tracker = SessionTracker()

    /// Start of the session in progress, nil when none is active.
    @Published public private(set) var sessionStart: Date? = nil
    var currentSessionStartTime: Date? { sessionStart }

    /// Where the session in progress stands: walking, paused (no steps for a
    /// while) or stopping (the user tapped Stop and the belt is winding down).
    @Published public private(set) var sessionPhase: SessionTracker.Phase = .idle

    /// When a paused session will end if walking doesn't resume.
    @Published public private(set) var pauseDeadline: Date? = nil

    /// Current session stats — reset on each new session start.
    @Published public var sessionSteps: Int = 0
    @Published public var sessionDistance: Int = 0

    /// Today's total distance fetched from Notion (set after session ends).
    @Published public var todayTotalDistance: Int = 0

    /// The session that just ended, shown as "Session saved" in the popover until
    /// the popover has been seen (or `recentSessionLifetime` passes).
    @Published public private(set) var recentSession: SessionSaveData? = nil
    /// When `recentSession` ended, used for the menu bar's brief "+0.42 km".
    public private(set) var recentSessionEndedAt: Date? = nil
    private let recentSessionLifetime: TimeInterval = 10 * 60

    /// Progress of the "Done for today" Strava post.
    @Published public var finishDayState: FinishDayState = .none

    enum FinishDayState: Equatable {
        case none
        case posting
        case posted
        case failed
    }

    /// Tracks whether we've already sent the 60-min notification for the current session.
    private var hasNotifiedForCurrentSession: Bool = false

    /// When the daily totals last reached disk. Saving only on speed changes means a
    /// steady hour-long walk never triggers one, so this bounds the exposure.
    private var lastSaveTime: Date = .distantPast

    /// Longest a session may run without the daily totals being written.
    private let maxSaveInterval: TimeInterval = 60

    /// Whether a checkpoint file is currently on disk, so an idle day does not
    /// delete a file that is not there once every polling interval.
    private var hasCheckpoint = false

    /// A session recovered from a crash checkpoint at launch, waiting for
    /// `onSessionComplete` to be wired up. Until it is flushed the recovery exists
    /// only in workouts.json, and Notion and Strava still know nothing about it.
    private(set) var pendingRecoveredSession: SessionSaveData? = nil

    /// Called when a session completes. Used to push to Notion.
    public var onSessionComplete: ((SessionSaveData, Int) -> Void)? = nil

    /// Called when the duration limit is hit. Passes the target speed (raw, tenths of km/h).
    public var onSpeedNudge: ((UInt8) -> Void)? = nil

    /// Called after every session phase change so the status bar can redraw.
    public var onSessionStateChange: (() -> Void)? = nil

    init() {
        self.load()
    }

    /// Sends a macOS notification if the current session has been going for 60+ minutes.
    /// Only fires once per session.
    private func sendWalkingDurationNotificationIfNeeded() {
        guard let start = tracker.start, !hasNotifiedForCurrentSession else { return }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed >= 3600 else { return }

        hasNotifiedForCurrentSession = true

        let content = UNMutableNotificationContent()
        content.title = "WalkingPad"
        content.body = "You've been walking for an hour. Take a break!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "walkingpad.duration.60min",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        appLog("60-min walking notification sent, reducing speed to 1.5 km/h")

        // Nudge: slow the treadmill to 1.5 km/h to encourage stopping
        onSpeedNudge?(15)
    }

    /// Zeroes daily counters if the date has changed since the last update.
    /// A session still running across midnight is closed first so it isn't lost.
    public func resetIfDateChanged() {
        guard !Calendar.current.isDateInToday(self.lastUpdateTime) else { return }

        if let event = tracker.finishNow() {
            appLog("SESSION END: day rolled over")
            handle([event])
        }
        self.hasNotifiedForCurrentSession = false
        self.lastUpdateTime = Date()
        DispatchQueue.main.async {
            self.distance = 0
            self.steps = 0
            self.walkingSeconds = 0
            self.todaySessions = []
            self.todayTotalDistance = 0
            self.recentSession = nil
            self.recentSessionEndedAt = nil
            self.finishDayState = .none
        }
    }

    /// Processes a BLE state update by computing diffs and accumulating daily totals.
    /// Guards against negative diffs (treadmill reset) and initial reconnection state.
    /// @Published mutations are deferred to the next main run loop iteration to avoid
    /// "Publishing changes from within view updates" warnings.
    public func update(_ oldState: DeviceState?, _ newState: DeviceState) {
        self.resetIfDateChanged()

        // Skip the first update after connection — oldState is nil so we can't compute
        // a meaningful diff (newState contains the treadmill's cumulative counters since power-on).
        guard let oldState = oldState else { return }

        let stepDiff = newState.steps - oldState.steps
        let distanceDiff = newState.distance - oldState.distance
        let walkingTimeDiff = newState.walkingTimeSeconds - oldState.walkingTimeSeconds

        let events = tracker.ingest(
            previous: SessionTracker.Sample(time: oldState.time, speed: oldState.speed, steps: oldState.steps, distance: oldState.distance),
            current: SessionTracker.Sample(time: newState.time, speed: newState.speed, steps: newState.steps, distance: newState.distance)
        )

        // Guard against negative diffs (treadmill counter reset)
        if stepDiff < 0 || distanceDiff < 0 {
            handle(events)
            return
        }

        // Speed changes are the natural save point, but a steady walk produces none
        // for as long as it lasts — so also save on a timer while one is running.
        if oldState.speed != newState.speed || Date().timeIntervalSince(lastSaveTime) >= maxSaveInterval {
            lastSaveTime = Date()
            save()
        }

        appLog("adding steps=\(stepDiff) distance=\(distanceDiff) speed=\(newState.speed) phase=\(tracker.phase)")

        if tracker.isActive {
            sendWalkingDurationNotificationIfNeeded()
        }

        // Defer @Published mutations to avoid SwiftUI re-entrancy warnings
        DispatchQueue.main.async {
            self.steps = self.steps + stepDiff
            self.distance = self.distance + distanceDiff
            self.walkingSeconds = self.walkingSeconds + max(0, walkingTimeDiff)
            self.lastUpdateTime = newState.time
        }

        handle(events)
    }

    /// Advances session timing without a treadmill frame. Called every second so a
    /// session still pauses and ends when the treadmill goes quiet.
    public func tick(now: Date = Date()) {
        let events = tracker.tick(now: now)
        if !events.isEmpty {
            handle(events)
        }
        if let endedAt = recentSessionEndedAt, now.timeIntervalSince(endedAt) > recentSessionLifetime {
            dismissRecentSession()
        }
    }

    /// The user tapped Stop. The session ends as soon as the belt confirms.
    public func requestStop() {
        tracker.requestStop(at: Date())
        publishSessionState()
    }

    /// Clears the "Session saved" state once it has been seen.
    public func dismissRecentSession() {
        guard recentSession != nil || recentSessionEndedAt != nil else { return }
        DispatchQueue.main.async {
            self.recentSession = nil
            self.recentSessionEndedAt = nil
            if self.finishDayState != .posting {
                self.finishDayState = .none
            }
            self.onSessionStateChange?()
        }
    }

    /// Applies tracker events: logging, checkpointing, and completing sessions.
    private func handle(_ events: [SessionTracker.Event]) {
        var completed: SessionSaveData? = nil

        for event in events {
            switch event {
            case .started(let start):
                appLog("SESSION START at \(start)")
                hasNotifiedForCurrentSession = false
            case .paused:
                appLog("SESSION PAUSED: no steps for \(Int(tracker.config.pauseAfter))s or belt reported speed 0")
            case .resumed:
                appLog("SESSION RESUMED")
            case .ended(let session):
                appLog("SESSION END: steps=\(session.steps), dist=\(session.distance), \(session.start) → \(session.end)")
                completed = SessionSaveData(startTime: session.start, endTime: session.end, steps: session.steps, distance: session.distance)
                hasNotifiedForCurrentSession = false
            case .discarded:
                appLog("SESSION DISCARDED: belt ran without any steps")
            }
        }

        // Mirror the in-flight session to disk on every update, and clear it the
        // moment one ends. `todaySessions` only gains a session at the end, so
        // without this an app death mid-walk keeps the distance in the daily total
        // but loses the session — and Notion and Strava are both fed from sessions.
        if let start = tracker.start, let lastActivity = tracker.lastActivity {
            SessionCheckpoint(
                startTime: start,
                lastUpdate: lastActivity,
                steps: tracker.steps,
                distance: tracker.distance
            ).save()
            hasCheckpoint = true
        } else if hasCheckpoint {
            SessionCheckpoint.clear()
            hasCheckpoint = false
        }

        publishSessionState()

        guard let session = completed else { return }
        DispatchQueue.main.async {
            appLog("SESSION COMPLETE: appending session #\(self.todaySessions.count + 1), steps=\(session.steps), dist=\(session.distance)")
            self.todaySessions.append(session)
            self.recentSession = session
            self.recentSessionEndedAt = Date()
            self.finishDayState = .none
            self.save()
            self.onSessionComplete?(session, self.todaySessions.count)
            self.onSessionStateChange?()
        }
    }

    /// Mirrors the tracker's state into the published properties the UI reads.
    private func publishSessionState() {
        let start = tracker.start
        let phase = tracker.phase
        let deadline = tracker.pauseDeadline
        let steps = tracker.steps
        let distance = tracker.distance
        DispatchQueue.main.async {
            if self.sessionStart != start { self.sessionStart = start }
            if self.sessionPhase != phase { self.sessionPhase = phase }
            if self.pauseDeadline != deadline { self.pauseDeadline = deadline }
            self.sessionSteps = steps
            self.sessionDistance = distance
            if start != nil && self.recentSession != nil {
                // Walking again replaces the "Session saved" state.
                self.recentSession = nil
                self.recentSessionEndedAt = nil
            }
            self.onSessionStateChange?()
        }
    }

    /// Today's distance in meters: Notion is the source of truth once sessions
    /// have synced, but local accumulation covers unsynced walking.
    public var todayDistance: Int {
        max(todayTotalDistance, distance)
    }

    /// Persists the current day's workout data to workouts.json.
    /// Replaces today's entry in the history and writes the full array.
    public func save() {
        let workoutData = WorkoutSaveData(
            steps: self.steps,
            distance: self.distance,
            walkingSeconds: self.walkingSeconds,
            date: self.lastUpdateTime,
            sessions: self.todaySessions.isEmpty ? nil : self.todaySessions
        )
        let withoutToday = loadAll().filter { !Calendar.current.isDateInToday($0.date)}
        let newData = withoutToday + [workoutData];
        
        let jsonEncoder = JSONEncoder()
        do {
            let json = try jsonEncoder.encode(WorkoutsSaveData(workouts: newData))
            FileSystem().save(filename: "workouts.json", data: json)
        } catch {
            appLog("could not save")
        }

        updateWidgetData()
    }
    
    /// Restores today's workout data from persisted storage on app launch.
    public func load() {
        if (self.steps > 0) {
            return
        }
        let workouts = loadAll()
        let workout = workouts.first (where: { entry in Calendar.current.isDateInToday(entry.date) })
    
        if let foundWorkout = workout {
            self.steps = foundWorkout.steps
            self.distance = foundWorkout.distance
            self.walkingSeconds = foundWorkout.walkingSeconds
            self.lastUpdateTime = foundWorkout.date
            self.todaySessions = foundWorkout.sessions ?? []
        }

        recoverInterruptedSession()
    }

    /// Restores a session that was still running when the app last died.
    ///
    /// A checkpoint on disk at launch means the previous run never reached the
    /// session-end path. The walking happened and is already inside the daily
    /// totals, but it never became a `SessionSaveData`, so as far as Notion and
    /// Strava are concerned it does not exist. Recover it as a session that ended
    /// at its last recorded update.
    private func recoverInterruptedSession() {
        guard let checkpoint = SessionCheckpoint.load() else { return }
        SessionCheckpoint.clear()

        guard Calendar.current.isDateInToday(checkpoint.startTime) else {
            appLog("Discarding an interrupted session from \(checkpoint.startTime) — not today", type: .error)
            return
        }
        guard checkpoint.distance > 0 || checkpoint.steps > 0 else { return }

        // A checkpoint written moments before a clean session end would otherwise be
        // recovered on top of the session it duplicates.
        let alreadyRecorded = todaySessions.contains {
            abs($0.startTime.timeIntervalSince(checkpoint.startTime)) < 1
        }
        guard !alreadyRecorded else { return }

        let recovered = SessionSaveData(
            startTime: checkpoint.startTime,
            endTime: checkpoint.lastUpdate,
            steps: checkpoint.steps,
            distance: checkpoint.distance
        )
        todaySessions.append(recovered)
        todaySessions.sort { $0.startTime < $1.startTime }
        pendingRecoveredSession = recovered
        appLog("Recovered an interrupted session: \(recovered.distance)m, \(recovered.steps) steps, ended \(checkpoint.lastUpdate)",
               type: .success)

        reconcileTotalsWithSessions()
        save()
    }

    /// The daily totals accumulate on every update while sessions are only appended
    /// when one ends, so the totals may legitimately lead the session list — but they
    /// must never trail it. After a recovery they can, if the crash also cost the
    /// last totals write.
    private func reconcileTotalsWithSessions() {
        let sessionDistance = todaySessions.reduce(0) { $0 + $1.distance }
        let sessionSteps = todaySessions.reduce(0) { $0 + $1.steps }

        if sessionDistance > self.distance {
            appLog("Daily distance (\(self.distance)m) trailed the recorded sessions (\(sessionDistance)m) — raising it")
            self.distance = sessionDistance
        }
        if sessionSteps > self.steps {
            self.steps = sessionSteps
        }
    }

    /// Fires `onSessionComplete` for a session recovered at launch. Call once, after
    /// the callback has been wired up — `load()` runs from `init()`, long before it
    /// exists, so without this the recovery never leaves the local file.
    public func flushRecoveredSession() {
        guard let session = pendingRecoveredSession else { return }
        pendingRecoveredSession = nil
        appLog("Pushing the recovered session to Notion", type: .success)
        onSessionComplete?(session, todaySessions.count)
    }

    /// Loads all historical workout entries. Silently truncates to the most recent 500.
    public func loadAll() -> [WorkoutSaveData] {
        let jsonDecoder = JSONDecoder()
        do {
            let optionalData = FileSystem().load(filename: "workouts.json")
            if let data = optionalData {
                let workoutData = try jsonDecoder.decode(WorkoutsSaveData.self, from: data)
                return workoutData.workouts.suffix(500)
            }
            return []
        } catch {
            appLog("Could not load workout data \(error)")
            return []
        }
    }
    
    public func workoutState() -> WorkoutState {
        return WorkoutState(steps: self.steps, distance: self.distance, walkingSeconds: self.walkingSeconds)
    }

    /// Computes the last 7 days of walking data and writes it to the shared App Group
    /// UserDefaults so the widget extension can display it.
    /// - Parameter workouts: Workout data to use. Falls back to local workouts.json if nil.
    public func updateWidgetData(from workouts: [WorkoutSaveData]? = nil) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let allWorkouts = workouts ?? loadAll()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var dailyDistances: [DailyDistance] = []
        for dayOffset in stride(from: 6, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let workout = allWorkouts.first { calendar.isDate($0.date, inSameDayAs: date) }
            dailyDistances.append(DailyDistance(
                dateString: formatter.string(from: date),
                distance: workout?.distance ?? 0,
                steps: workout?.steps ?? 0
            ))
        }

        let widgetData = WidgetData(
            weeklyDistances: dailyDistances,
            totalDistanceMeters: dailyDistances.reduce(0) { $0 + $1.distance },
            lastUpdated: Date()
        )
        if let error = widgetData.write() {
            // The widget's container is another app's container — macOS privacy
            // protection can deny the write; surface it instead of going stale silently.
            appLog("Widget data write failed: \(error.localizedDescription)", type: .error)
        }
    }
}
