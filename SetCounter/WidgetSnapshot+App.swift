import Foundation
import WidgetKit

extension WidgetSnapshot {
    /// Rebuilds the snapshot from the records (newest first) and current settings.
    static func write(records: [WorkoutRecord], now: Date = Date()) {
        let calendar = Calendar.current
        let names = Routine.savedNames
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let workoutDays = Set(records.map { calendar.startOfDay(for: $0.date) })
        let weekDone = (0..<7).map { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart).map { workoutDays.contains($0) } ?? false
        }
        let defaults = UserDefaults.standard

        WidgetSnapshot(
            date: now,
            routineNames: names,
            todayIndex: Routine.todayIndex(count: names.count, records: records, now: now),
            workedOutToday: Routine.workedOutToday(records: records, now: now),
            weekStart: weekStart,
            weekDone: weekDone,
            weeklyGoal: defaults.object(forKey: "weeklyGoal") as? Int ?? 4,
            accent: defaults.string(forKey: "accent") ?? "blue"
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
