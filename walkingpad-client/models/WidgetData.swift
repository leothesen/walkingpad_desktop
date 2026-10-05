import Foundation

/// One day's walking totals for the widget.
struct WidgetDay: Codable, Equatable {
    let dateString: String   // "2026-04-15"
    let distance: Int        // meters
    let steps: Int
    let seconds: Int
}

/// The daily goal as the widget sees it. Mirrors `GoalSettings` in the main app,
/// which can't be compiled into the widget (it depends on UserDefaults and app logging).
struct WidgetGoal: Codable, Equatable {
    enum Kind: String, Codable {
        case distance
        case steps
        case time
    }

    let kind: Kind
    /// In the kind's unit: km, steps or minutes.
    let value: Double

    /// A day's amount of the goal's quantity, in the goal's unit.
    func amount(of day: WidgetDay) -> Double {
        switch kind {
        case .distance: return Double(day.distance) / 1000
        case .steps: return Double(day.steps)
        case .time: return Double(day.seconds) / 60
        }
    }

    /// Fraction of the goal reached (can exceed 1).
    func progress(of day: WidgetDay) -> Double {
        guard value > 0 else { return 0 }
        return amount(of: day) / value
    }

    var unit: String {
        switch kind {
        case .distance: return "km"
        case .steps: return "steps"
        case .time: return "min"
        }
    }

    /// Formats an amount in this goal's unit, without the unit.
    func format(_ amount: Double) -> String {
        switch kind {
        case .distance:
            if amount >= 10 { return String(format: "%.1f", amount) }
            return String(format: "%.2f", amount)
        case .steps:
            return Int(amount).formatted()
        case .time:
            return String(Int(amount))
        }
    }

    /// Formats the goal itself: "8", "8.5", "12,000", "90".
    var formattedValue: String {
        switch kind {
        case .distance:
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
        case .steps, .time:
            return Int(value).formatted()
        }
    }
}

/// Snapshot of recent walking data shared between the main app and the widget extension.
///
/// The main app (non-sandboxed) writes `widgetData.json` into the widget extension's
/// sandbox container. The widget (sandboxed) reads from its own container. No App Groups needed.
struct WidgetData: Codable {
    /// Recent days, sorted oldest to newest. Days without walking may be missing.
    let days: [WidgetDay]
    let goal: WidgetGoal
    let lastUpdated: Date

    /// How many days of history the app sends: enough for the widest grid.
    static let historyDays = 7 * 16

    private static let filename = "widgetData.json"
    private static let widgetBundleID = "klassm.walkingpad-client.WalkingPadWidget"

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The day for `date`, or an empty day when nothing was recorded.
    func day(for date: Date) -> WidgetDay {
        let key = Self.dateString(date)
        return days.last { $0.dateString == key }
            ?? WidgetDay(dateString: key, distance: 0, steps: 0, seconds: 0)
    }

    /// The dot grid: `weeks` columns of 7 days, oldest column first, ending with the
    /// week that contains `today`. Rows follow the calendar's first weekday.
    /// Days after `today` are nil.
    func grid(weeks: Int, today: Date, calendar: Calendar = .current) -> [[WidgetDay?]] {
        guard weeks > 0 else { return [] }
        let todayStart = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: todayStart)
        let row = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -row - (weeks - 1) * 7, to: todayStart) else { return [] }

        return (0..<weeks).map { week in
            (0..<7).map { index -> WidgetDay? in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + index, to: start),
                      date <= todayStart else { return nil }
                return day(for: date)
            }
        }
    }

    /// Path used by the **main app** to write into the widget's sandbox container.
    /// Works because the main app is non-sandboxed and can write to any path.
    private static var widgetContainerDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Documents")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Path used by the **widget** to read from its own sandbox container.
    private static var sandboxDocumentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Reads widget data from the Documents directory (used by the widget).
    static func read() -> WidgetData? {
        let url = sandboxDocumentsDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    /// Writes widget data into the widget's container (used by the main app).
    /// This file is also compiled into the widget target, which has no ActivityLog —
    /// so the error is returned for the caller to log rather than logged here.
    @discardableResult
    func write() -> Error? {
        let url = Self.widgetContainerDirectory.appendingPathComponent(Self.filename)
        guard let encoded = try? JSONEncoder().encode(self) else { return nil }
        do {
            try encoded.write(to: url, options: .atomic)
            return nil
        } catch {
            return error
        }
    }
}
