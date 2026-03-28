import Foundation
import SwiftUI

enum TimeRange: String, CaseIterable {
    case week = "7 Days"
    case month = "30 Days"
    case allTime = "Monthly"
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

    let allWorkouts: [WorkoutSaveData]

    init(workouts: [WorkoutSaveData]) {
        self.allWorkouts = workouts
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
        case .allTime:
            return allWorkouts
        }
    }

    /// Previous period for trend comparison (e.g., prior 7 days for week view).
    private var previousPeriodWorkouts: [WorkoutSaveData] {
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
        case .allTime:
            return []
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

    /// Percentage change in distance vs previous period. Nil for allTime.
    var distanceTrend: Double? {
        guard selectedRange != .allTime else { return nil }
        let previous = previousPeriodWorkouts.reduce(0) { $0 + $1.distance }
        guard previous > 0 else {
            return totalDistance > 0 ? 100.0 : 0
        }
        return (Double(totalDistance - previous) / Double(previous)) * 100.0
    }

    // MARK: - Formatted Strings

    var distanceText: String {
        let km = Double(totalDistance) / 1000.0
        if km >= 10 {
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

    // MARK: - Chart Data

    var dailyPoints: [DailyPoint] {
        if selectedRange == .allTime {
            return monthlyPoints
        }
        return filteredWorkouts.map { w in
            DailyPoint(
                date: w.date,
                distance: w.distance,
                steps: w.steps,
                walkingSeconds: w.walkingSeconds,
                sessionCount: w.sessions?.count ?? (w.steps > 0 ? 1 : 0)
            )
        }.sorted { $0.date < $1.date }
    }

    private var monthlyPoints: [DailyPoint] {
        let calendar = Calendar.current
        var grouped: [DateComponents: (distance: Int, steps: Int, seconds: Int, sessions: Int)] = [:]

        for w in filteredWorkouts {
            let components = calendar.dateComponents([.year, .month], from: w.date)
            var existing = grouped[components] ?? (0, 0, 0, 0)
            existing.distance += w.distance
            existing.steps += w.steps
            existing.seconds += w.walkingSeconds
            existing.sessions += w.sessions?.count ?? (w.steps > 0 ? 1 : 0)
            grouped[components] = existing
        }

        return grouped.compactMap { (components, data) -> DailyPoint? in
            guard let date = calendar.date(from: components) else { return nil }
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
        case .allTime:
            guard let first = allWorkouts.first?.date else { return 0 }
            return max(1, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0)
        }
    }
}
