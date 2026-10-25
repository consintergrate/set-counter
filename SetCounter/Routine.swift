import Foundation

/// Split routine: the parts rotate in order, one step per workout day.
enum Routine {
    static let namesKey = "routineNames"
    static let defaultRaw = defaultNames(for: 3).joined(separator: "|")

    static func defaultNames(for split: Int) -> [String] {
        switch split {
        case 1: [String(localized: "전신")]
        case 2: [String(localized: "상체"), String(localized: "하체")]
        case 3: [String(localized: "가슴·삼두"), String(localized: "등·이두"), String(localized: "하체·어깨")]
        case 4: [String(localized: "가슴"), String(localized: "등"), String(localized: "어깨"), String(localized: "하체")]
        case 5: [String(localized: "가슴"), String(localized: "등"), String(localized: "어깨"), String(localized: "하체"), String(localized: "팔")]
        default: [String(localized: "가슴"), String(localized: "등"), String(localized: "어깨"), String(localized: "하체"), String(localized: "팔"), String(localized: "복근·유산소")]
        }
    }

    static func names(from raw: String) -> [String] {
        let names = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return names.isEmpty ? defaultNames(for: 3) : names
    }

    static var savedNames: [String] {
        names(from: UserDefaults.standard.string(forKey: namesKey) ?? defaultRaw)
    }

    /// The most recent routine workout, if any. `records` must be newest first.
    private static func lastRoutineRecord(in records: [WorkoutRecord]) -> WorkoutRecord? {
        records.first { $0.routineIndex >= 0 }
    }

    static func workedOutToday(records: [WorkoutRecord], now: Date = Date()) -> Bool {
        records.contains { Calendar.current.isDate($0.date, inSameDayAs: now) }
    }

    /// Today's part: a manual pick for today wins; if a routine workout was already
    /// done today, it stays on that part; otherwise the one after the last workout.
    static func todayIndex(count: Int, records: [WorkoutRecord], now: Date = Date()) -> Int {
        guard count > 0 else { return 0 }
        let defaults = UserDefaults.standard
        if let overrideDay = defaults.object(forKey: "routineOverrideDay") as? Double,
           Calendar.current.isDate(Date(timeIntervalSince1970: overrideDay), inSameDayAs: now) {
            return defaults.integer(forKey: "routineOverrideIndex") % count
        }
        guard let last = lastRoutineRecord(in: records) else { return 0 }
        let index = last.routineIndex % count
        return Calendar.current.isDate(last.date, inSameDayAs: now) ? index : (index + 1) % count
    }

    static func setTodayOverride(_ index: Int, now: Date = Date()) {
        UserDefaults.standard.set(Calendar.current.startOfDay(for: now).timeIntervalSince1970, forKey: "routineOverrideDay")
        UserDefaults.standard.set(index, forKey: "routineOverrideIndex")
    }

    /// Distinct workout days in the week containing `now`.
    static func weeklyDays(records: [WorkoutRecord], now: Date = Date()) -> Int {
        let calendar = Calendar.current
        return Set(records
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .weekOfYear) }
            .map { calendar.startOfDay(for: $0.date) }
        ).count
    }
}
