import Foundation

/// The daily walking goal: drives the menu bar ring, the popover progress bar and
/// the green in the stats window's history. Stored in UserDefaults.
final class GoalSettings: ObservableObject {
    static let shared = GoalSettings()

    enum Kind: String, CaseIterable, Identifiable {
        case distance
        case steps
        case time

        var id: String { rawValue }

        var label: String {
            switch self {
            case .distance: return "Distance"
            case .steps: return "Steps"
            case .time: return "Time"
            }
        }

        var unit: String {
            switch self {
            case .distance: return "km"
            case .steps: return "steps"
            case .time: return "min"
            }
        }

        var step: Double {
            switch self {
            case .distance: return 0.5
            case .steps: return 500
            case .time: return 5
            }
        }

        var presets: [Double] {
            switch self {
            case .distance: return [5, 8, 10, 12]
            case .steps: return [8_000, 10_000, 12_000, 15_000]
            case .time: return [45, 60, 90, 120]
            }
        }

        var defaultValue: Double {
            switch self {
            case .distance: return 10
            case .steps: return 12_000
            case .time: return 90
            }
        }

        /// Formats a value in this kind's unit, without the unit.
        func format(_ value: Double) -> String {
            switch self {
            case .distance:
                return value.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", value)
                    : String(format: "%.1f", value)
            case .steps:
                return Int(value).formatted()
            case .time:
                return String(Int(value))
            }
        }
    }

    private static let kindKey = "goal.kind"
    private static let valueKey = "goal.value"

    @Published private(set) var kind: Kind
    @Published private(set) var value: Double

    private init() {
        let defaults = UserDefaults.standard
        let kind = Kind(rawValue: defaults.string(forKey: Self.kindKey) ?? "") ?? .distance
        let stored = defaults.double(forKey: Self.valueKey)
        self.kind = kind
        self.value = stored > 0 ? stored : kind.defaultValue
    }

    func set(kind: Kind, value: Double) {
        let clamped = max(kind.step, value)
        self.kind = kind
        self.value = clamped
        UserDefaults.standard.set(kind.rawValue, forKey: Self.kindKey)
        UserDefaults.standard.set(clamped, forKey: Self.valueKey)
        appLog("Daily goal set to \(kind.format(clamped)) \(kind.unit)")
    }

    /// "10 km", "12,000 steps", "90 min".
    var label: String { "\(kind.format(value)) \(kind.unit)" }

    /// A day's amount of the goal's quantity, in the goal's unit.
    func amount(distanceMeters: Int, steps: Int, seconds: Int) -> Double {
        switch kind {
        case .distance: return Double(distanceMeters) / 1000
        case .steps: return Double(steps)
        case .time: return Double(seconds) / 60
        }
    }

    /// Fraction of the goal reached (can exceed 1).
    func progress(distanceMeters: Int, steps: Int, seconds: Int) -> Double {
        guard value > 0 else { return 0 }
        return amount(distanceMeters: distanceMeters, steps: steps, seconds: seconds) / value
    }

    /// Estimated walking time to reach the goal at `speedKmh`, or nil when the goal
    /// isn't distance/time based or is already met.
    func timeToGoal(distanceMeters: Int, steps: Int, seconds: Int, speedKmh: Double) -> TimeInterval? {
        let remaining = value - amount(distanceMeters: distanceMeters, steps: steps, seconds: seconds)
        guard remaining > 0 else { return nil }
        switch kind {
        case .distance:
            guard speedKmh > 0 else { return nil }
            return remaining / speedKmh * 3600
        case .time:
            return remaining * 60
        case .steps:
            return nil
        }
    }
}
