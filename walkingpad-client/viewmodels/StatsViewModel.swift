import Foundation
import SwiftUI

enum TimeRange: String, CaseIterable {
    case week = "7 Days"
    case month = "30 Days"
    case allTime = "Monthly"
}

/// Represents a single bar in the daily/monthly chart.
struct DailyBar: Identifiable {
    let id = UUID()
    let date: Date
    let distance: Int
    let steps: Int
    let walkingSeconds: Int
    let sessionCount: Int
}

/// Represents one cell in the activity heatmap (day-of-week x hour-of-day).
struct HeatmapCell: Identifiable {
    let id = UUID()
    let dayOfWeek: Int   // 1=Sun ... 7=Sat (Calendar default)
    let dayLabel: String // Mon, Tue, etc.
    let hour: Int        // 0-23
    let distance: Double // meters
}

/// Computes derived stats from raw workout data for the stats window.
class StatsViewModel: ObservableObject {
    @Published var selectedRange: TimeRange = .week

    let allWorkouts: [WorkoutSaveData]

    init(workouts: [WorkoutSaveData]) {
        self.allWorkouts = workouts
    }

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

    var totalDistance: Int { filteredWorkouts.reduce(0) { $0 + $1.distance } }
    var totalSteps: Int { filteredWorkouts.reduce(0) { $0 + $1.steps } }
    var totalWalkingSeconds: Int { filteredWorkouts.reduce(0) { $0 + $1.walkingSeconds } }

    var totalSessions: Int {
        filteredWorkouts.reduce(0) { total, w in
            total + (w.sessions?.count ?? (w.steps > 0 ? 1 : 0))
        }
    }

    /// Formatted distance string (e.g., "12.3 km" or "850 m").
    var distanceText: String {
        let meters = totalDistance
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000.0)
        }
        return "\(meters) m"
    }

    /// Formatted walking time string.
    var timeText: String {
        let hours = totalWalkingSeconds / 3600
        let minutes = (totalWalkingSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Daily Bar Data

    var dailyBars: [DailyBar] {
        if selectedRange == .allTime {
            return monthlyBars
        }
        return filteredWorkouts.map { w in
            DailyBar(
                date: w.date,
                distance: w.distance,
                steps: w.steps,
                walkingSeconds: w.walkingSeconds,
                sessionCount: w.sessions?.count ?? (w.steps > 0 ? 1 : 0)
            )
        }.sorted { $0.date < $1.date }
    }

    /// Aggregated by month for the "Monthly" view.
    private var monthlyBars: [DailyBar] {
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

        return grouped.compactMap { (components, data) -> DailyBar? in
            guard let date = calendar.date(from: components) else { return nil }
            return DailyBar(
                date: date,
                distance: data.distance,
                steps: data.steps,
                walkingSeconds: data.seconds,
                sessionCount: data.sessions
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Heatmap Data

    var heatmapData: [HeatmapCell] {
        let calendar = Calendar.current
        let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        // Accumulate distance per (dayOfWeek, hour) slot
        var grid: [Int: [Int: Double]] = [:]  // [dayOfWeek: [hour: distance]]
        for day in 1...7 {
            grid[day] = [:]
        }

        for w in filteredWorkouts {
            if let sessions = w.sessions {
                for session in sessions {
                    let dow = calendar.component(.weekday, from: session.startTime)
                    let hour = calendar.component(.hour, from: session.startTime)
                    grid[dow, default: [:]][hour, default: 0] += Double(session.distance)
                }
            } else if w.steps > 0 {
                // Fallback: place at the date's hour
                let dow = calendar.component(.weekday, from: w.date)
                let hour = calendar.component(.hour, from: w.date)
                grid[dow, default: [:]][hour, default: 0] += Double(w.distance)
            }
        }

        var cells: [HeatmapCell] = []
        for day in 1...7 {
            for hour in stride(from: 6, to: 23, by: 2) {
                let dist = (grid[day]?[hour] ?? 0) + (grid[day]?[hour + 1] ?? 0)
                cells.append(HeatmapCell(
                    dayOfWeek: day,
                    dayLabel: dayLabels[day - 1],
                    hour: hour,
                    distance: dist
                ))
            }
        }
        return cells
    }

    var maxHeatmapDistance: Double {
        heatmapData.map(\.distance).max() ?? 1
    }
}
