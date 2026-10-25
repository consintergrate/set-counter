import Foundation

/// What the home screen widget shows, written by the app into the shared App Group.
/// It stores enough to stay correct after midnight or a new week without the app running.
struct WidgetSnapshot: Codable {
    static let appGroup = "group.com.andykim.SetCounter"
    private static let key = "widgetSnapshot"

    var date: Date
    var routineNames: [String]
    var todayIndex: Int
    var workedOutToday: Bool
    var weekStart: Date
    /// Workout or not for each day of `weekStart`'s week, in display order.
    var weekDone: [Bool]
    var weeklyGoal: Int
    var accent: String

    static let placeholder = WidgetSnapshot(
        date: Date(),
        routineNames: [String(localized: "가슴·삼두"), String(localized: "등·이두"), String(localized: "하체·어깨")],
        todayIndex: 0,
        workedOutToday: false,
        weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date(),
        weekDone: [false, true, false, true, false, false, false],
        weeklyGoal: 4,
        accent: "blue"
    )

    /// The part for `now`: once the snapshot's day is over, a finished workout moves the rotation on.
    func index(at now: Date) -> Int {
        guard !routineNames.isEmpty else { return 0 }
        if Calendar.current.isDate(date, inSameDayAs: now) || !workedOutToday { return todayIndex }
        return (todayIndex + 1) % routineNames.count
    }

    func todayName(at now: Date) -> String {
        routineNames.isEmpty ? "" : routineNames[index(at: now)]
    }

    func splitLabel(at now: Date) -> String {
        routineNames.count <= 1
            ? String(localized: "무분할 루틴")
            : String(localized: "\(routineNames.count)분할 · \(index(at: now) + 1)일차")
    }

    var splitLabel: String { splitLabel(at: Date()) }

    func isCurrentWeek(at now: Date) -> Bool {
        Calendar.current.isDate(weekStart, equalTo: now, toGranularity: .weekOfYear)
    }

    func weekDone(at now: Date) -> [Bool] {
        isCurrentWeek(at: now) ? weekDone : Array(repeating: false, count: 7)
    }

    func weeklyDays(at now: Date) -> Int { weekDone(at: now).filter { $0 }.count }

    var weeklyDays: Int { weeklyDays(at: Date()) }

    static func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}
