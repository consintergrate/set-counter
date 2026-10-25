import Foundation
import UserNotifications

/// Morning reminders like "오늘은 등·이두 하는 날이에요". Rotation depends on what was
/// actually done, so the next two weeks are rescheduled whenever records or settings change.
@MainActor
enum RoutineNotifications {
    private static let prefix = "routine-"
    static let weeklyReportID = "weekly-report"
    static let weeklyReportKey = "weeklyReportOn"
    private static let horizonDays = 21
    private static let maxScheduled = 14

    static let defaultTime = 8 * 3600
    static let defaultWeekdaysRaw = "2,3,4,5,6"

    private static let cheers = [
        String(localized: "화이팅 해보아요! 💪"),
        String(localized: "오늘도 한 세트씩 쌓아봐요 🔥"),
        String(localized: "어제보다 한 걸음 더! 화이팅 🙌"),
        String(localized: "시작이 반이에요. 가볍게 출발해요 🏃"),
    ]

    static func weekdays(from raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0) })
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func message(for name: String, cheerIndex: Int = 0) -> String {
        String(localized: "오늘은 \(name) 하는 날이에요. \(cheers[cheerIndex % cheers.count])")
    }

    /// 8 p.m. on the last day of the week (Saturday where weeks start on Sunday, as in
    /// Korea), while the toggle is on and notifications are allowed.
    static func scheduleWeeklyReport() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyReportID])
        guard UserDefaults.standard.object(forKey: weeklyReportKey) as? Bool ?? true,
              await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "📊 이번 주 리포트가 도착했어요")
        content.body = String(localized: "근력·유산소·식단·체중을 한눈에 확인해 보세요.")
        content.sound = .default
        let lastWeekday = (Calendar.current.firstWeekday + 5) % 7 + 1
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 20, minute: 0, weekday: lastWeekday), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: weeklyReportID, content: content, trigger: trigger))
    }

    /// `records` must be newest first.
    static func reschedule(records: [WorkoutRecord], now: Date = Date()) async {
        await scheduleWeeklyReport()
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let defaults = UserDefaults.standard
        let names = Routine.savedNames
        guard defaults.bool(forKey: "notifyOn"), !names.isEmpty,
              await center.notificationSettings().authorizationStatus == .authorized else { return }

        let time = defaults.object(forKey: "notifyTime") as? Int ?? defaultTime
        let weekdays = weekdays(from: defaults.string(forKey: "notifyWeekdays") ?? defaultWeekdaysRaw)
        let weeklyGoal = defaults.object(forKey: "weeklyGoal") as? Int ?? 4
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let doneToday = Routine.workedOutToday(records: records, now: now)
        var next = Routine.todayIndex(count: names.count, records: records, now: now)
        if doneToday { next = (next + 1) % names.count }
        // Projected days done this week, assuming each reminded day gets a workout.
        var weekDone = Routine.weeklyDays(records: records, now: now)

        var scheduled = 0
        for offset in 0..<horizonDays where scheduled < maxScheduled {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let fire = calendar.date(byAdding: .second, value: time, to: day) else { continue }
            if offset == 0, doneToday || fire <= now { continue }

            let name = names[next]
            let content = UNMutableNotificationContent()
            content.title = String(localized: "💪 오늘은 \(name) 데이")
            var body = message(for: name, cheerIndex: offset)
            if calendar.isDate(day, equalTo: now, toGranularity: .weekOfYear) {
                let remaining = weeklyGoal - weekDone
                body += remaining > 0 ? "\n" + String(localized: "이번 주 목표까지 \(remaining)일 남았어요.") : "\n" + String(localized: "이번 주 목표는 이미 달성했어요. 보너스 운동!")
                weekDone += 1
            }
            content.body = body
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(
                identifier: prefix + "\(offset)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
            next = (next + 1) % names.count
            scheduled += 1
        }
    }
}
