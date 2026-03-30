import SwiftUI
import Foundation

public typealias OnChangeCallback = (_ change: Change) -> Void

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
    private var currentSessionStart: Date? = nil
    private var currentSessionSteps: Int = 0
    private var currentSessionDistance: Int = 0

    public var onChangeCallback: OnChangeCallback =  {_ in }
    
    init() {
        self.load()
    }
    
    /// Zeroes daily counters if the date has changed since the last update.
    /// Note: only compares day-of-month, not full date — see KNOWN_ISSUES.md #9.
    public func resetIfDateChanged() {
        let now = Date()
        if now.get(.day) != self.lastUpdateTime.get(.day) && self.steps > 0 {
            self.currentSessionStart = nil
            self.currentSessionSteps = 0
            self.currentSessionDistance = 0
            DispatchQueue.main.async {
                self.distance = 0
                self.steps = 0
                self.walkingSeconds = 0
                self.todaySessions = []
            }
        }
    }
    
    /// Processes a BLE state update by computing diffs and accumulating daily totals.
    /// Guards against negative diffs (treadmill reset) and initial reconnection state.
    /// Fires `onChangeCallback` with a Change struct for the StepsUploader.
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

        print("adding steps=\(stepDiff) distance=\(distanceDiff)")

        if (self.steps > 0 && newState.statusType == .currentStatus) {
            let change = Change(
                oldTime: self.lastUpdateTime,
                newTime: newState.time,
                stepsDiff: stepDiff,
                oldSpeed: oldState.speed,
                newSpeed: newState.speed
            )
            self.onChangeCallback(change)
        }

        // Session tracking (non-published state, safe to update synchronously)
        let wasWalking = oldState.speed > 0
        let isWalking = newState.speed > 0

        if isWalking && !wasWalking {
            self.currentSessionStart = newState.time
            self.currentSessionSteps = 0
            self.currentSessionDistance = 0
        }

        if self.currentSessionStart != nil {
            self.currentSessionSteps += stepDiff
            self.currentSessionDistance += distanceDiff
        }

        var completedSession: SessionSaveData? = nil
        if wasWalking && !isWalking, let sessionStart = self.currentSessionStart {
            completedSession = SessionSaveData(
                startTime: sessionStart,
                endTime: newState.time,
                steps: self.currentSessionSteps,
                distance: self.currentSessionDistance
            )
            self.currentSessionStart = nil
            self.currentSessionSteps = 0
            self.currentSessionDistance = 0
        }

        // Defer @Published mutations to avoid SwiftUI re-entrancy warnings
        DispatchQueue.main.async {
            self.steps = self.steps + stepDiff
            self.distance = self.distance + distanceDiff
            self.walkingSeconds = self.walkingSeconds + walkingTimeDiff
            self.lastUpdateTime = newState.time

            if let session = completedSession {
                self.todaySessions.append(session)
                self.save()
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
            print("could not save")
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
            print("Could not load workout data \(error)")
            return []
        }
    }
    
    public func workoutState() -> WorkoutState {
        return WorkoutState(steps: self.steps, distance: self.distance, walkingSeconds: self.walkingSeconds)
    }
}
