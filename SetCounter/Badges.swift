import SwiftUI

enum BadgeTier: Int, Codable {
    case special, bronze, silver, gold, platinum

    /// Medallion gradient, light to dark.
    var colors: [Color] {
        switch self {
        case .special: [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 0.13, green: 0.32, blue: 0.85)]
        case .bronze: [Color(red: 0.93, green: 0.64, blue: 0.40), Color(red: 0.62, green: 0.36, blue: 0.18)]
        case .silver: [Color(red: 0.86, green: 0.88, blue: 0.92), Color(red: 0.55, green: 0.58, blue: 0.65)]
        case .gold: [Color(red: 1.0, green: 0.84, blue: 0.36), Color(red: 0.86, green: 0.55, blue: 0.08)]
        // The app's own navy and ember, as on the launch screen.
        case .platinum: [Color(red: 1.0, green: 0.42, blue: 0.10), Color(red: 0.071, green: 0.086, blue: 0.227)]
        }
    }

    var title: String {
        switch self {
        case .special: String(localized: "스페셜")
        case .bronze: String(localized: "브론즈")
        case .silver: String(localized: "실버")
        case .gold: String(localized: "골드")
        case .platinum: String(localized: "플래티넘")
        }
    }
}

enum BadgeFamily: String, CaseIterable, Identifiable {
    case firsts, consistency, totals, records
    var id: Self { self }

    var title: String {
        switch self {
        case .firsts: String(localized: "첫걸음")
        case .consistency: String(localized: "꾸준함")
        case .totals: String(localized: "누적")
        case .records: String(localized: "기록")
        }
    }
}

/// What a badge counts. Each metric has one value and the date it first reached
/// each goal, worked out from the whole history.
enum BadgeMetric: Hashable {
    case firstWorkout, firstRecord, firstCardio, firstMeal, firstWeight
    case workoutDays, weekGoalStreak, dayStreak
    case totalSets, totalVolume, cardioKm
    case recordCount
    case lift(BigLift)
}

enum BigLift: String, CaseIterable, Hashable {
    case bench, squat, deadlift

    var title: String {
        switch self {
        case .bench: String(localized: "벤치프레스")
        case .squat: String(localized: "스쿼트")
        case .deadlift: String(localized: "데드리프트")
        }
    }

    /// The barbell lift itself, not its variations (incline bench, split squat, RDL…).
    func matches(_ name: String) -> Bool {
        let n = ExerciseLibrary.normalized(name)
        func has(_ words: [String]) -> Bool { words.contains { n.contains($0) } }
        switch self {
        case .bench:
            return has(["벤치프레스", "benchpress"]) && !has(["인클라인", "incline", "디클라인", "decline", "클로즈", "close", "덤벨", "dumbbell", "머신", "machine"])
        case .squat:
            return has(["스쿼트", "squat"]) && !has(["스플릿", "split", "불가리안", "bulgarian", "고블릿", "goblet", "점프", "jump"])
        case .deadlift:
            return has(["데드리프트", "deadlift"]) && !has(["루마니안", "romanian", "rdl", "스티프", "stiff", "싱글", "single"])
        }
    }
}

struct BadgeDefinition: Identifiable, Hashable {
    let id: String
    let family: BadgeFamily
    let tier: BadgeTier
    let systemImage: String
    let metric: BadgeMetric
    let goal: Double

    var title: String {
        let n = Int(goal)
        switch metric {
        case .firstWorkout: return String(localized: "첫 운동")
        case .firstRecord: return String(localized: "첫 신기록")
        case .firstCardio: return String(localized: "첫 유산소 연동")
        case .firstMeal: return String(localized: "첫 식단 기록")
        case .firstWeight: return String(localized: "첫 체중 기록")
        case .workoutDays: return String(localized: "badge.workoutDays", defaultValue: "운동 \(n)일")
        case .weekGoalStreak: return String(localized: "badge.weekStreak", defaultValue: "\(n)주 연속 목표")
        case .dayStreak: return String(localized: "badge.dayStreak", defaultValue: "\(n)일 연속 운동")
        case .totalSets: return String(localized: "badge.totalSets", defaultValue: "세트 \(n.formatted())개")
        case .totalVolume: return String(localized: "badge.totalVolume", defaultValue: "\((n / 1000).formatted())톤 클럽")
        case .cardioKm: return String(localized: "badge.cardioKm", defaultValue: "유산소 \(n)km")
        case .recordCount: return String(localized: "badge.recordCount", defaultValue: "신기록 \(n)개")
        case .lift(let lift): return String(localized: "badge.lift", defaultValue: "\(lift.title) 체중의 \(goal.formatted())배")
        }
    }

    var detail: String {
        switch metric {
        case .firstWorkout: String(localized: "세트 카운터로 첫 운동을 기록했어요.")
        case .firstRecord: String(localized: "처음으로 개인 기록을 깼어요.")
        case .firstCardio: String(localized: "다른 앱에서 한 러닝·걷기가 처음 들어왔어요.")
        case .firstMeal: String(localized: "먹은 것을 처음 기록했어요.")
        case .firstWeight: String(localized: "체중을 처음 기록했어요.")
        case .workoutDays: String(localized: "세트 카운터로 운동한 날을 세요.")
        case .weekGoalStreak: String(localized: "주간 목표 일수를 채운 주가 이어진 최고 기록이에요.")
        case .dayStreak: String(localized: "하루도 빠짐없이 운동한 최고 연속 일수예요.")
        case .totalSets: String(localized: "지금까지 마친 모든 세트를 더해요.")
        case .totalVolume: String(localized: "무게 × 횟수를 모든 세트에서 더한 총 볼륨이에요.")
        case .cardioKm: String(localized: "건강 앱에 저장된 최근 1년의 러닝·걷기·사이클 거리를 더해요.")
        case .recordCount: String(localized: "운동별 최고 무게(맨몸은 최고 횟수)를 넘긴 횟수예요.")
        case .lift: String(localized: "한 세트라도 이 무게를 들면 받아요. 기준 체중은 설정의 내 정보예요.")
        }
    }

    /// "23/30일" style progress text.
    func progressText(_ value: Double) -> String {
        let shown = min(value, goal)
        switch metric {
        case .firstWorkout, .firstRecord, .firstCardio, .firstMeal, .firstWeight:
            return value >= 1 ? String(localized: "완료") : String(localized: "아직이에요")
        case .workoutDays, .dayStreak:
            return String(localized: "\(Int(shown))/\(Int(goal))일")
        case .weekGoalStreak:
            return String(localized: "\(Int(shown))/\(Int(goal))주")
        case .totalSets, .recordCount:
            return "\(Int(shown).formatted())/\(Int(goal).formatted())"
        case .totalVolume:
            return "\(formatMass(shown))/\(formatMass(goal))"
        case .cardioKm:
            return "\(formatDistance(shown * 1000))/\(Int(goal))km"
        case .lift:
            return String(localized: "badge.liftProgress", defaultValue: "지금 \(value.formatted(.number.precision(.fractionLength(2))))배")
        }
    }

    // MARK: The badges

    static let all: [BadgeDefinition] = {
        var badges: [BadgeDefinition] = [
            BadgeDefinition(id: "first-workout", family: .firsts, tier: .special, systemImage: "figure.strengthtraining.traditional", metric: .firstWorkout, goal: 1),
            BadgeDefinition(id: "first-record", family: .firsts, tier: .special, systemImage: "trophy.fill", metric: .firstRecord, goal: 1),
            BadgeDefinition(id: "first-cardio", family: .firsts, tier: .special, systemImage: "figure.run", metric: .firstCardio, goal: 1),
            BadgeDefinition(id: "first-meal", family: .firsts, tier: .special, systemImage: "fork.knife", metric: .firstMeal, goal: 1),
            BadgeDefinition(id: "first-weight", family: .firsts, tier: .special, systemImage: "scalemass.fill", metric: .firstWeight, goal: 1),
        ]
        let tiers: [BadgeTier] = [.bronze, .silver, .gold, .platinum]
        func ladder(_ key: String, _ family: BadgeFamily, _ image: String, _ metric: BadgeMetric, _ goals: [Double]) {
            for (goal, tier) in zip(goals, tiers) {
                // Ids are stored, so they must not depend on the locale's number format.
                let goalText = goal == goal.rounded() ? String(Int(goal)) : String(goal)
                badges.append(BadgeDefinition(id: "\(key)-\(goalText)", family: family, tier: tier,
                                              systemImage: image, metric: metric, goal: goal))
            }
        }
        ladder("workout-days", .consistency, "calendar.badge.checkmark", .workoutDays, [10, 30, 100, 300])
        ladder("week-streak", .consistency, "flame.fill", .weekGoalStreak, [2, 4, 12, 26])
        ladder("day-streak", .consistency, "bolt.fill", .dayStreak, [3, 7])
        ladder("sets", .totals, "square.stack.3d.up.fill", .totalSets, [100, 500, 1000, 5000])
        ladder("volume", .totals, "dumbbell.fill", .totalVolume, [10_000, 50_000, 100_000, 1_000_000])
        ladder("cardio-km", .totals, "figure.run", .cardioKm, [10, 50, 100, 500])
        ladder("records", .records, "trophy.fill", .recordCount, [10, 30, 100])
        ladder("bench", .records, "figure.strengthtraining.traditional", .lift(.bench), [0.75, 1, 1.25])
        ladder("squat", .records, "figure.cross.training", .lift(.squat), [1, 1.5, 2])
        ladder("deadlift", .records, "figure.strengthtraining.functional", .lift(.deadlift), [1.25, 1.75, 2.25])
        return badges
    }()
}

/// Where a badge stands: its current value and, once reached, when.
struct BadgeProgress: Equatable {
    var value: Double = 0
    var achievedAt: Date?

    func fraction(goal: Double) -> Double { goal > 0 ? min(value / goal, 1) : 0 }
}

/// Plain values the engine works from, so it can be tested without SwiftData or Health.
struct BadgeInput {
    struct Workout {
        let date: Date
        let exercise: String
        let sets: Int
        let volume: Double
        let bestWeight: Double
        let maxReps: Int
    }

    var workouts: [Workout] = []
    /// Cardio sessions from other apps: start date and distance in km.
    var cardio: [(date: Date, km: Double)] = []
    var firstMeal: Date?
    var firstWeight: Date?
    var bodyWeight: Double = 70
    var weeklyGoal: Int = 4
    var now = Date()
}

enum BadgeEngine {
    /// Progress for every badge in `BadgeDefinition.all`, keyed by id.
    static func progress(_ input: BadgeInput, calendar: Calendar = .current) -> [String: BadgeProgress] {
        let workouts = input.workouts.sorted { $0.date < $1.date }

        // Each metric as (date, running value) steps; a goal is reached at the first step at or above it.
        var series: [BadgeMetric: [(date: Date, value: Double)]] = [:]

        var days: [Date] = []
        var sets = 0.0, volume = 0.0
        var setSteps: [(Date, Double)] = [], volumeSteps: [(Date, Double)] = []
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.date)
            if days.last != day { days.append(day) }
            sets += Double(workout.sets)
            volume += workout.volume
            setSteps.append((workout.date, sets))
            volumeSteps.append((workout.date, volume))
        }
        // The first record of each workout day.
        let dayFirsts = days.map { day in workouts.first { calendar.isDate($0.date, inSameDayAs: day) }?.date ?? day }
        series[.workoutDays] = dayFirsts.enumerated().map { ($1, Double($0 + 1)) }
        series[.totalSets] = setSteps
        series[.totalVolume] = volumeSteps
        if let first = workouts.first { series[.firstWorkout] = [(first.date, 1)] }

        // Personal records: beating the best weight (or reps, for bodyweight) of earlier sessions.
        var bestWeight: [String: Double] = [:], bestReps: [String: Int] = [:]
        var recordSteps: [(Date, Double)] = []
        for workout in workouts where !workout.exercise.isEmpty {
            let name = workout.exercise
            if let previous = bestWeight[name] {
                let beat = workout.bestWeight > 0 ? workout.bestWeight > previous : workout.maxReps > (bestReps[name] ?? 0)
                if beat { recordSteps.append((workout.date, Double(recordSteps.count + 1))) }
            }
            bestWeight[name] = max(bestWeight[name] ?? 0, workout.bestWeight)
            bestReps[name] = max(bestReps[name] ?? 0, workout.maxReps)
        }
        series[.recordCount] = recordSteps
        if let first = recordSteps.first { series[.firstRecord] = [(first.0, 1)] }

        // Big lifts against body weight, as the best so far grows.
        for lift in BigLift.allCases {
            var best = 0.0
            var steps: [(Date, Double)] = []
            for workout in workouts where lift.matches(workout.exercise) && workout.bestWeight > best {
                best = workout.bestWeight
                steps.append((workout.date, best / max(input.bodyWeight, 1)))
            }
            series[.lift(lift)] = steps
        }

        // Streaks: best run so far after each workout day.
        var dayRun = 0, bestDayRun = 0, dayStreakSteps: [(Date, Double)] = []
        for (index, day) in days.enumerated() {
            let follows = index > 0 && calendar.date(byAdding: .day, value: 1, to: days[index - 1]) == day
            dayRun = follows ? dayRun + 1 : 1
            if dayRun > bestDayRun {
                bestDayRun = dayRun
                dayStreakSteps.append((dayFirsts[index], Double(bestDayRun)))
            }
        }
        series[.dayStreak] = dayStreakSteps
        series[.weekGoalStreak] = weekStreakSteps(days: days, dayFirsts: dayFirsts, goal: input.weeklyGoal, now: input.now, calendar: calendar)

        let cardio = input.cardio.sorted { $0.date < $1.date }
        var km = 0.0
        series[.cardioKm] = cardio.map { km += $0.km; return ($0.date, km) }
        if let first = cardio.first { series[.firstCardio] = [(first.date, 1)] }
        if let firstMeal = input.firstMeal { series[.firstMeal] = [(firstMeal, 1)] }
        if let firstWeight = input.firstWeight { series[.firstWeight] = [(firstWeight, 1)] }

        var result: [String: BadgeProgress] = [:]
        for badge in BadgeDefinition.all {
            let steps = series[badge.metric] ?? []
            // Values only grow, except lift ratios, which can drop if body weight rises;
            // the best ratio reached is what counts.
            let value = steps.map(\.value).max() ?? 0
            let reached = steps.first { $0.value >= badge.goal - 1e-9 }?.date
            result[badge.id] = BadgeProgress(value: value, achievedAt: reached)
        }
        return result
    }

    /// Weeks in a row with at least `goal` workout days. The week in progress only
    /// extends a streak; it can't break one until it's over.
    static func weekStreakSteps(days: [Date], dayFirsts: [Date], goal: Int, now: Date, calendar: Calendar) -> [(date: Date, value: Double)] {
        guard goal > 0, let firstDay = days.first,
              var week = calendar.dateInterval(of: .weekOfYear, for: firstDay)?.start,
              let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var run = 0, best = 0
        var steps: [(Date, Double)] = []
        while week <= currentWeek {
            let inWeek = days.indices.filter { calendar.isDate(days[$0], equalTo: week, toGranularity: .weekOfYear) }
            if inWeek.count >= goal {
                run += 1
                if run > best {
                    best = run
                    // Reached on the day the goal-th workout of the week was done.
                    steps.append((dayFirsts[inWeek[goal - 1]], Double(best)))
                }
            } else if week < currentWeek {
                run = 0
            }
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }
        return steps
    }
}
