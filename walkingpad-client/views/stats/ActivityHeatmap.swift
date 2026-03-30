import SwiftUI

/// A compact consistency indicator showing which days in the period had activity.
/// Replaces the full heatmap with a simpler, more glanceable view.
struct ConsistencyStreak: View {
    let activeDays: Int
    let totalDays: Int
    let workouts: [WorkoutSaveData]

    private var recentDays: [(date: Date, active: Bool)] {
        let calendar = Calendar.current
        let count = min(totalDays, 14) // Show up to 14 day dots
        let today = calendar.startOfDay(for: Date())

        return (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let isActive = workouts.contains { w in
                calendar.isDate(w.date, inSameDayAs: date) && w.steps > 0
            }
            return (date: date, active: isActive)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(activeDays)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("of \(totalDays) days active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 3) {
                ForEach(Array(recentDays.enumerated()), id: \.offset) { _, day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.active ? Color.blue.opacity(0.8) : Color.primary.opacity(0.06))
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                }
            }

            HStack {
                Text(dayLabel(recentDays.first?.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Today")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func dayLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
