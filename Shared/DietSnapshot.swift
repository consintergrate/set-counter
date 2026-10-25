import Foundation

/// Calories and cardio for the diet widget, written by the app whenever it reads
/// Health. Widgets can't read Health while the phone is locked, so the widget
/// shows the last values and resets them itself at midnight and on a new week.
struct DietSnapshot: Codable {
    private static let key = "dietSnapshot"

    var date: Date
    /// Base daily target (BMR minus the planned deficit).
    var target: Double
    var eaten: Double
    /// Active energy recorded today; added to what can be eaten.
    var active: Double
    var weekStart: Date
    var cardioMinutes: Int
    var cardioGoal: Int
    var accent: String

    static let placeholder = DietSnapshot(
        date: Date(), target: 1600, eaten: 1240, active: 320,
        weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date(),
        cardioMinutes: 90, cardioGoal: 150, accent: "blue"
    )

    private func isToday(_ now: Date) -> Bool { Calendar.current.isDate(date, inSameDayAs: now) }

    func eaten(at now: Date) -> Double { isToday(now) ? eaten : 0 }
    func active(at now: Date) -> Double { isToday(now) ? active : 0 }
    func allowance(at now: Date) -> Double { target + active(at: now) }
    func remaining(at now: Date) -> Double { allowance(at: now) - eaten(at: now) }

    func cardioMinutes(at now: Date) -> Int {
        Calendar.current.isDate(weekStart, equalTo: now, toGranularity: .weekOfYear) ? cardioMinutes : 0
    }

    static func read() -> DietSnapshot? {
        guard let data = UserDefaults(suiteName: WidgetSnapshot.appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DietSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(data, forKey: Self.key)
    }
}
