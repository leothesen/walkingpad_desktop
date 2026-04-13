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
/// - Resets daily counters at midnight (checked every polling interval)
/// - Fires `onChangeCallback` for the StepsUploader to detect treadmill stop events
/// - Saves on speed changes; keeps up to 500 historical workout entries
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

    // Session tracking state
    /// Exposed for status bar display of session duration.
    private(set) var currentSessionStart: Date? = nil
    var currentSessionStartTime: Date? { currentSessionStart }

    /// Current session stats — reset on each new session start.
    @Published public var sessionSteps: Int = 0
    @Published public var sessionDistance: Int = 0

    private var currentSessionSteps: Int = 0
    private var currentSessionDistance: Int = 0

    /// Today's total distance fetched from Notion (set after session ends).
    @Published public var todayTotalDistance: Int = 0
    /// Count of consecutive zero-step updates while a session is active.
    /// Used to detect belt stop even when the treadmill keeps reporting non-zero speed.
    private var consecutiveZeroStepUpdates: Int = 0
    private let zeroStepThreshold: Int = 3  // ~12 seconds at 4s polling

    /// Idle detection progress shown in the UI (0 when not idle, 1...threshold during detection).
    @Published public var idleProgress: Int = 0
    /// Set when user explicitly taps Stop — triggers immediate idle UI.
    @Published public var isStopping: Bool = false
    /// Session save state shown in the UI.
    @Published public var sessionSaveState: SessionSaveState = .none

    enum SessionSaveState: Equatable {
        case none
        case saving
        case uploading
        case complete
    }

    /// Tracks whether we've already sent the 60-min notification for the current session.
    private var hasNotifiedForCurrentSession: Bool = false

    /// Called when a session completes (speed → 0). Used to push to Notion.
    public var onSessionComplete: ((SessionSaveData, Int) -> Void)? = nil

    /// Called when the duration limit is hit. Passes the target speed (raw, tenths of km/h).
    public var onSpeedNudge: ((UInt8) -> Void)? = nil
    
    init() {
        self.load()
    }

    /// Sends a macOS notification if the current session has been going for 60+ minutes.
    /// Only fires once per session.
    private func sendWalkingDurationNotificationIfNeeded() {
        guard let start = currentSessionStart, !hasNotifiedForCurrentSession else { return }
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
    public func resetIfDateChanged() {
        if !Calendar.current.isDateInToday(self.lastUpdateTime) {
            self.currentSessionStart = nil
            self.currentSessionSteps = 0
            self.currentSessionDistance = 0
            self.consecutiveZeroStepUpdates = 0
            self.hasNotifiedForCurrentSession = false
            self.lastUpdateTime = Date()
            DispatchQueue.main.async {
                self.distance = 0
                self.steps = 0
                self.walkingSeconds = 0
                self.todaySessions = []
                self.todayTotalDistance = 0
            }
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

        // Guard against negative diffs (treadmill counter reset)
        if stepDiff < 0 || distanceDiff < 0 {
            return
        }
        if oldState.speed != newState.speed {
            save()
        }

        appLog("adding steps=\(stepDiff) distance=\(distanceDiff)")

        // Session tracking (non-published state, safe to update synchronously)
        let wasWalking = oldState.speed > 0
        let isWalking = newState.speed > 0

        if isWalking && !wasWalking && self.currentSessionStart == nil {
            appLog("SESSION START: speed \(oldState.speed) → \(newState.speed)")
            self.currentSessionStart = newState.time
            self.currentSessionSteps = 0
            self.currentSessionDistance = 0
            self.consecutiveZeroStepUpdates = 0
            self.hasNotifiedForCurrentSession = false
            DispatchQueue.main.async {
                self.idleProgress = 0
                self.isStopping = false
                self.sessionSaveState = .none
            }
        }

        // Also start a session if we're getting steps but no session is active
        // (happens when treadmill was already moving on first valid state pair)
        if isWalking && stepDiff > 0 && self.currentSessionStart == nil {
            appLog("SESSION START (mid-walk): speed=\(newState.speed), steps already flowing")
            self.currentSessionStart = newState.time
            self.currentSessionSteps = 0
            self.currentSessionDistance = 0
            self.consecutiveZeroStepUpdates = 0
            self.hasNotifiedForCurrentSession = false
        }

        if self.currentSessionStart != nil {
            self.currentSessionSteps += stepDiff
            self.currentSessionDistance += distanceDiff

            // Check if we need to send the 60-minute notification
            sendWalkingDurationNotificationIfNeeded()

            // Track consecutive zero-step updates to detect belt stop.
            // Only start counting after we've seen at least one step in this session
            // to avoid false idle on session start.
            if stepDiff == 0 && self.currentSessionSteps > 0 {
                self.consecutiveZeroStepUpdates += 1
                appLog("SESSION IDLE: \(self.consecutiveZeroStepUpdates)/\(self.zeroStepThreshold) zero-step updates, speed=\(newState.speed)")
            } else {
                self.consecutiveZeroStepUpdates = 0
            }
            // Update idle progress for UI
            DispatchQueue.main.async {
                self.idleProgress = self.consecutiveZeroStepUpdates
            }
        }

        // End session when: explicit speed→0 transition, OR belt appears stopped
        // (several consecutive updates with no steps while session is active)
        let beltStopped = self.currentSessionStart != nil && self.consecutiveZeroStepUpdates >= self.zeroStepThreshold
        var completedSession: SessionSaveData? = nil

        if (wasWalking && !isWalking || beltStopped), let sessionStart = self.currentSessionStart {
            appLog("SESSION END: speed \(oldState.speed) → \(newState.speed), steps=\(self.currentSessionSteps), dist=\(self.currentSessionDistance), reason=\(beltStopped ? "idle" : "speed→0")")
            completedSession = SessionSaveData(
                startTime: sessionStart,
                endTime: newState.time,
                steps: self.currentSessionSteps,
                distance: self.currentSessionDistance
            )
            self.currentSessionStart = nil
            self.currentSessionSteps = 0
            self.currentSessionDistance = 0
            self.consecutiveZeroStepUpdates = 0
            self.hasNotifiedForCurrentSession = false
        }

        // Defer @Published mutations to avoid SwiftUI re-entrancy warnings
        DispatchQueue.main.async {
            self.steps = self.steps + stepDiff
            self.distance = self.distance + distanceDiff
            self.walkingSeconds = self.walkingSeconds + walkingTimeDiff
            self.lastUpdateTime = newState.time

            // Update current session published values
            self.sessionSteps = self.currentSessionSteps
            self.sessionDistance = self.currentSessionDistance

            if let session = completedSession {
                self.idleProgress = 0
                self.isStopping = false
                self.sessionSaveState = .saving
                appLog("SESSION COMPLETE: appending session #\(self.todaySessions.count + 1), steps=\(session.steps), dist=\(session.distance)")
                self.todaySessions.append(session)
                self.sessionSteps = 0
                self.sessionDistance = 0
                self.save()
                self.onSessionComplete?(session, self.todaySessions.count)
                // Show "complete" after a short delay, then clear — unless
                // stopAndFinishDay takes over and drives its own states
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.sessionSaveState == .saving {
                        self.sessionSaveState = .complete
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if self.sessionSaveState == .complete {
                        self.sessionSaveState = .none
                    }
                }
            }
        }

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
}
