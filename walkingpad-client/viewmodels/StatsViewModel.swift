import Foundation
import SwiftUI

enum TimeRange: String, CaseIterable {
    case week = "7 Days"
    case month = "30 Days"
    case monthly = "Monthly"
    case yearly = "Yearly"
    case allTime = "All Time"
}

/// How chart points are bucketed for the selected range.
enum ChartGranularity {
    case day    // one bar per day (7 Days, 30 Days)
    case month  // one bar per month (Monthly, All Time)
    case year   // one bar per year (Yearly)
}

/// A single data point for the trend chart and daily breakdowns.
struct DailyPoint: Identifiable {
    let id = UUID()
    let date: Date
    let distance: Int      // meters
    let steps: Int
    let walkingSeconds: Int
    let sessionCount: Int

    var distanceKm: Double { Double(distance) / 1000.0 }
}

/// Computes derived stats from raw workout data for the stats dashboard.
class StatsViewModel: ObservableObject {
    @Published var selectedRange: TimeRange = .week
    @Published var hoveredPoint: DailyPoint? = nil
    @Published var isLoading: Bool = false
    @Published var dataSource: String = "local"

    @Published var allWorkouts: [WorkoutSaveData]

    init(workouts: [WorkoutSaveData]) {
        self.allWorkouts = workouts
    }

    /// Replace workout data (e.g., after fetching from Notion) and trigger re-render.
    func replaceWorkouts(_ workouts: [WorkoutSaveData], source: String = "local") {
        self.allWorkouts = workouts
        self.dataSource = source
        self.isLoading = false
    }

    var granularity: ChartGranularity {
        switch selectedRange {
        case .week, .month: return .day
        case .monthly, .allTime: return .month
        case .yearly: return .year
        }
    }

    // MARK: - Filtering

    var filteredWorkouts: [WorkoutSaveData] {
        let now = Date()
        let calendar = Calendar.current
        switch selectedRange {
        case .week:
            let cutoff = calendar.date(byAdding: .day, value: -7, to: now)!
            return allWorkouts.filter { $0.date >= cutoff }
        case .month:
            let cutoff = calendar.date(byAdding: .day, value: -30, to: now)!
            return allWorkouts.filter { $0.date >= cutoff }
        case .monthly:
            // Last 12 calendar months including the current one
            let startOfMonth = calendar.dateInterval(of: .month, for: now)!.start
            let cutoff = calendar.date(byAdding: .month, value: -11, to: startOfMonth)!
            return allWorkouts.filter { $0.date >= cutoff }
        case .yearly, .allTime:
            return allWorkouts
        }
    }

    /// Previous period for trend comparison. Nil when there is no meaningful
    /// "previous" window (Yearly, All Time).
    private var previousPeriodWorkouts: [WorkoutSaveData]? {
        let now = Date()
        let calendar = Calendar.current
        switch selectedRange {
        case .week:
            let start = calendar.date(byAdding: .day, value: -14, to: now)!
            let end = calendar.date(byAdding: .day, value: -7, to: now)!
            return allWorkouts.filter { $0.date >= start && $0.date < end }
        case .month:
            let start = calendar.date(byAdding: .day, value: -60, to: now)!
            let end = calendar.date(byAdding: .day, value: -30, to: now)!
            return allWorkouts.filter { $0.date >= start && $0.date < end }
        case .monthly:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)!.start
            let end = calendar.date(byAdding: .month, value: -11, to: startOfMonth)!
            let start = calendar.date(byAdding: .month, value: -12, to: end)!
            return allWorkouts.filter { $0.date >= start && $0.date < end }
        case .yearly, .allTime:
            return nil
        }
    }

    // MARK: - Totals

    var totalDistance: Int { filteredWorkouts.reduce(0) { $0 + $1.distance } }
    var totalSteps: Int { filteredWorkouts.reduce(0) { $0 + $1.steps } }
    var totalWalkingSeconds: Int { filteredWorkouts.reduce(0) { $0 + $1.walkingSeconds } }

    var totalSessions: Int {
        filteredWorkouts.reduce(0) { total, w in
            total + (w.sessions?.count ?? (w.steps > 0 ? 1 : 0))
        }
    }

    var averageSpeedKmh: Double {
        let totalSeconds = Double(totalWalkingSeconds)
        let totalKm = Double(totalDistance) / 1000.0
        guard totalSeconds > 0 else { return 0 }
        return totalKm / (totalSeconds / 3600.0)
    }

    // MARK: - Trend (vs previous period)

    /// Percentage change in distance vs previous period.
    /// Nil when there is no previous window or no data to compare against.
    var distanceTrend: Double? {
        guard let previousWorkouts = previousPeriodWorkouts else { return nil }
        let previous = previousWorkouts.reduce(0) { $0 + $1.distance }
        guard previous > 0 else { return nil }
        return (Double(totalDistance - previous) / Double(previous)) * 100.0
    }

    /// Label for what the trend is compared against, e.g. "vs previous 7 days".
    var trendComparisonLabel: String {
        switch selectedRange {
        case .week: return "vs previous 7 days"
        case .month: return "vs previous 30 days"
        case .monthly: return "vs previous 12 months"
        case .yearly, .allTime: return ""
        }
    }

    // MARK: - Highlights

    /// The single best day in the selected period.
    var bestDay: WorkoutSaveData? {
        filteredWorkouts.max { $0.distance < $1.distance }
    }

    /// Average distance per active day in the selected period, in meters.
    var averagePerActiveDay: Int {
        guard activeDays > 0 else { return 0 }
        return totalDistance / activeDays
    }

    /// Consecutive active days ending today (or yesterday, if today has no
    /// activity yet — an in-progress day shouldn't read as a broken streak).
    /// Computed over all data, independent of the selected range.
    var currentStreak: Int {
        let calendar = Calendar.current
        let activeDaySet = Set(
            allWorkouts.filter { $0.steps > 0 }.map { calendar.startOfDay(for: $0.date) }
        )
        guard !activeDaySet.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
        var day = activeDaySet.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today)!
        var streak = 0
        while activeDaySet.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    // MARK: - Formatted Strings

    var distanceText: String {
        let km = Double(totalDistance) / 1000.0
        if km >= 100 {
            return String(format: "%.0f", km)
        } else if km >= 1 {
            return String(format: "%.1f", km)
        } else {
            return "\(totalDistance)"
        }
    }

    var distanceUnit: String {
        totalDistance >= 1000 ? "km" : "m"
    }

    var timeText: String {
        let hours = totalWalkingSeconds / 3600
        let minutes = (totalWalkingSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var avgSpeedText: String {
        String(format: "%.1f", averageSpeedKmh)
    }

    var dailyAvgText: String {
        Self.shortDistance(averagePerActiveDay)
    }

    var bestDayText: String {
        guard let best = bestDay else { return "—" }
        return Self.shortDistance(best.distance)
    }

    var bestDayDateText: String {
        guard let best = bestDay else { return "Best day" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Best · \(formatter.string(from: best.date))"
    }

    static func shortDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000.0)
        }
        return "\(meters) m"
    }

    // MARK: - Chart Data

    var dailyPoints: [DailyPoint] {
        switch granularity {
        case .day:
            return filteredWorkouts.map { w in
                DailyPoint(
                    date: w.date,
                    distance: w.distance,
                    steps: w.steps,
                    walkingSeconds: w.walkingSeconds,
                    sessionCount: w.sessions?.count ?? (w.steps > 0 ? 1 : 0)
                )
            }.sorted { $0.date < $1.date }
        case .month:
            return groupedPoints(by: [.year, .month])
        case .year:
            return groupedPoints(by: [.year])
        }
    }

    private func groupedPoints(by components: Set<Calendar.Component>) -> [DailyPoint] {
        let calendar = Calendar.current
        var grouped: [DateComponents: (distance: Int, steps: Int, seconds: Int, sessions: Int)] = [:]

        for w in filteredWorkouts {
            let key = calendar.dateComponents(components, from: w.date)
            var existing = grouped[key] ?? (0, 0, 0, 0)
            existing.distance += w.distance
            existing.steps += w.steps
            existing.seconds += w.walkingSeconds
            existing.sessions += w.sessions?.count ?? (w.steps > 0 ? 1 : 0)
            grouped[key] = existing
        }

        return grouped.compactMap { (key, data) -> DailyPoint? in
            guard let date = calendar.date(from: key) else { return nil }
            return DailyPoint(
                date: date,
                distance: data.distance,
                steps: data.steps,
                walkingSeconds: data.seconds,
                sessionCount: data.sessions
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Streak / Consistency

    /// Number of days walked in the current period.
    var activeDays: Int {
        filteredWorkouts.filter { $0.steps > 0 }.count
    }

    /// Total days in the selected period.
    var periodDays: Int {
        switch selectedRange {
        case .week: return 7
        case .month: return 30
        case .monthly: return 365
        case .yearly, .allTime:
            guard let first = allWorkouts.map(\.date).min() else { return 0 }
            return max(1, (Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0) + 1)
        }
    }
}
