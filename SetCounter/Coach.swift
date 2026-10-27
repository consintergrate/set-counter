import SwiftUI

/// One line of advice on the home screen.
struct CoachTip: Identifiable {
    enum Kind { case rest, overEaten, weight, record, cardio, balance, steps, underEaten, done, routine }

    let kind: Kind
    let icon: String
    let color: Color
    let title: String
    let detail: String
    var id: Kind { kind }
}

/// An exercise for today's part with the next target to aim for.
struct RoutineSuggestion: Identifiable {
    let exercise: String
    let muscle: Muscle
    /// kg; 0 for bodyweight.
    let weight: Double
    let reps: Int
    let sets: Int
    let note: String
    /// No history yet: the numbers are a starting point, not progression.
    let isNew: Bool
    let doneToday: Bool
    var id: String { exercise }
}

/// The assistant's rule-based brain: everything it says is derived from the
/// workout records and the Health data already on the phone.
enum Coach {
    @MainActor
    static func tips(records: [WorkoutRecord], profiles: [ExerciseProfile], health: HealthData,
                     todayPart: String, goals: Goals = .saved, profile: BodyProfile = .saved,
                     now: Date = Date()) -> [CoachTip] {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let hasHealth = health.isAvailable && !health.needsAuthorization && health.lastRefresh != nil
        let strengthToday = records.contains { calendar.isDate($0.date, inSameDayAs: now) }
        var tips: [CoachTip] = []

        // Days since anything was done, counting other apps' workouts too.
        let lastStrength = records.first?.date
        let lastCardio = health.cardio.first?.start
        if let last = [lastStrength, lastCardio].compactMap({ $0 }).max(),
           let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day,
           days >= 3 {
            tips.append(CoachTip(kind: .rest, icon: "bed.double.fill", color: .indigo,
                                 title: String(localized: "\(days)일째 쉬고 있어요"),
                                 detail: String(localized: "오늘은 \(todayPart) 차례예요. 가볍게라도 시작하면 흐름이 다시 붙어요.")))
        }

        if hasHealth, health.todayEaten > 0 {
            let budget = CalorieBudget(goals: goals, profile: profile, health: health)
            if budget.remaining < -50 {
                let over = Int(-budget.remaining)
                tips.append(CoachTip(kind: .overEaten, icon: "fork.knife", color: .red,
                                     title: String(localized: "목표보다 \(over.formatted())kcal 더 먹었어요"),
                                     detail: String(localized: "러닝 \(runningMinutes(toBurn: -budget.remaining, weight: profile.weight))분이면 채울 수 있어요. 내일 조금 덜 먹어도 괜찮아요.")))
            } else if hour >= 20, budget.remaining > 500 {
                tips.append(CoachTip(kind: .underEaten, icon: "fork.knife", color: .orange,
                                     title: String(localized: "아직 \(Int(budget.remaining).formatted())kcal 남았어요"),
                                     detail: String(localized: "너무 적게 먹으면 근육이 빠질 수 있어요. 단백질 위주로 챙겨 드세요.")))
            }
        }

        if hasHealth {
            let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
            let recent = health.weights.filter { $0.date >= twoWeeksAgo }
            if let first = recent.first, let last = recent.last, first.date != last.date {
                let change = last.kg - first.kg
                let hasGoal = Goals.hasGoalWeight
                let toGo = last.kg - goals.goalWeight
                if hasGoal, goals.weeklyLoss > 0, toGo <= 0 {
                    tips.append(CoachTip(kind: .weight, icon: "party.popper.fill", color: .green,
                                         title: String(localized: "목표 체중에 도달했어요"),
                                         detail: String(localized: "이제 감량 속도를 '유지'로 바꾸면 유지 칼로리로 안내해 드려요.")))
                } else if change <= -0.2 {
                    tips.append(CoachTip(kind: .weight, icon: "chart.line.downtrend.xyaxis", color: .green,
                                         title: String(localized: "2주 동안 \(formatMass(-change)) 빠졌어요"),
                                         detail: !hasGoal
                                            ? String(localized: "홈의 체중 카드를 눌러 목표 체중을 정하면 남은 양도 알려드려요.")
                                            : toGo > 0
                                                ? String(localized: "목표까지 \(formatMass(toGo)) 남았어요. 지금 속도 좋아요.")
                                                : String(localized: "지금 속도를 유지해 보세요.")))
                } else if goals.weeklyLoss > 0, change >= 0.5 {
                    tips.append(CoachTip(kind: .weight, icon: "chart.line.uptrend.xyaxis", color: .orange,
                                         title: String(localized: "2주 동안 \(formatMass(change)) 늘었어요"),
                                         detail: String(localized: "먹은 칼로리를 기록해 보면 원인을 찾기 쉬워요.")))
                }
            }
        }

        if let pr = ExerciseBest.all(in: records).first,
           let date = pr.best.headlineDate,
           date > calendar.date(byAdding: .day, value: -2, to: now) ?? now {
            let value = pr.best.weight > 0 ? formatWeight(pr.best.weight) : String(localized: "\(pr.best.reps)회")
            tips.append(CoachTip(kind: .record, icon: "trophy.fill", color: .orange,
                                 title: String(localized: "\(pr.name) 신기록!"),
                                 detail: String(localized: "\(value) 달성. 꾸준함이 통하고 있어요.")))
        }

        if hasHealth, goals.cardioWeeklyMinutes > 0 {
            let done = Int(health.cardioMinutes(inWeekOf: now))
            let goal = goals.cardioWeeklyMinutes
            // Only when behind an even pace, so the first day of the week isn't a nag.
            if done < goal, let week = calendar.dateInterval(of: .weekOfYear, for: now),
               let daysLeft = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: week.end).day, daysLeft > 0,
               Double(done) < Double(goal) * Double(7 - daysLeft) / 7 {
                let perDay = Int((Double(goal - done) / Double(daysLeft)).rounded(.up))
                tips.append(CoachTip(kind: .cardio, icon: "figure.run", color: .teal,
                                     title: String(localized: "이번 주 유산소 \(goal - done)분 남았어요"),
                                     detail: String(localized: "남은 \(daysLeft)일 동안 하루 \(perDay)분씩이면 목표 달성이에요.")))
            }
        }

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let lastWeek = records.filter { $0.date >= weekAgo && !$0.exercise.isEmpty }
        if lastWeek.reduce(0, { $0 + $1.sets }) >= 12 {
            var counts: [Muscle: Int] = [:]
            for record in lastWeek { counts[Muscle.lookup(record.exercise, in: profiles), default: 0] += record.sets }
            let main: [Muscle] = [.chest, .back, .shoulders, .legs]
            if let weakest = main.min(by: { counts[$0] ?? 0 < counts[$1] ?? 0 }),
               counts[weakest] ?? 0 < 4, (counts.values.max() ?? 0) >= 10 {
                tips.append(CoachTip(kind: .balance, icon: "scalemass.fill", color: .purple,
                                     title: String(localized: "최근 7일 \(weakest.title) 운동이 부족해요"),
                                     detail: String(localized: "\(weakest.title) \(counts[weakest] ?? 0)세트 · 부위마다 주 10세트 이상이 좋아요.")))
            }
        }

        if hasHealth, hour >= 17, health.todaySteps > 0, Int(health.todaySteps) < goals.steps {
            let left = goals.steps - Int(health.todaySteps)
            tips.append(CoachTip(kind: .steps, icon: "shoeprints.fill", color: .green,
                                 title: String(localized: "걸음 \(left.formatted())보 남았어요"),
                                 detail: String(localized: "\(max(left / 100, 1))분 정도 걸으면 오늘 목표 달성이에요.")))
        }

        if strengthToday {
            let protein = Int((profile.weight * 1.6).rounded())
            tips.append(CoachTip(kind: .done, icon: "checkmark.seal.fill", color: .green,
                                 title: String(localized: "오늘 운동 완료!"),
                                 detail: String(localized: "회복을 위해 단백질 \(protein)g(체중 1kg당 1.6g)을 챙겨 드세요.")))
        } else if !tips.contains(where: { $0.kind == .rest }) {
            tips.append(CoachTip(kind: .routine, icon: "dumbbell.fill", color: .accentColor,
                                 title: String(localized: "오늘은 \(todayPart) 데이"),
                                 detail: String(localized: "아래 추천 루틴을 누르면 바로 준비 화면으로 가요.")))
        }

        return Array(tips.prefix(3))
    }

    // MARK: Recommended routine

    /// Muscles named in a routine part such as "가슴·삼두" or "Upper Body", in the order written.
    static func muscles(in part: String) -> [Muscle] {
        let text = part.lowercased()
        let table: [([String], [Muscle])] = [
            (["가슴", "chest"], [.chest]),
            (["등", "back"], [.back]),
            (["어깨", "shoulder"], [.shoulders]),
            (["이두", "bicep"], [.biceps]),
            (["삼두", "tricep"], [.triceps]),
            (["하체", "다리", "leg", "lower"], [.legs]),
            (["복근", "코어", "abs", "core"], [.core]),
            (["팔", "arm"], [.biceps, .triceps]),
            (["상체", "upper"], [.chest, .back, .shoulders]),
            (["전신", "full"], [.chest, .back, .legs, .shoulders]),
        ]
        var found: [(position: String.Index, muscles: [Muscle])] = []
        for (keywords, muscles) in table {
            if let position = keywords.compactMap({ text.range(of: $0)?.lowerBound }).min() {
                found.append((position, muscles))
            }
        }
        var seen = Set<Muscle>()
        return found.sorted { $0.position < $1.position }.flatMap(\.muscles).filter { seen.insert($0).inserted }
    }

    /// Starter exercises with a light first weight (kg) for parts without history.
    private static func library(for muscle: Muscle) -> [(name: String, weight: Double)] {
        ExerciseLibrary.exercises(for: muscle).filter(\.starter).map { ($0.name, $0.startWeight) }
    }

    /// Up to six exercises for `part`: the user's own most frequent lifts for those
    /// muscles with a progressive-overload target, topped up from a starter list.
    /// Without `progresses` (Pro) the numbers are simply last time's.
    static func recommendedRoutine(for part: String, records: [WorkoutRecord], profiles: [ExerciseProfile],
                                   unit: WeightUnit = .current, progresses: Bool = true,
                                   now: Date = Date()) -> [RoutineSuggestion] {
        let calendar = Calendar.current
        // A routine the user arranged wins; only the numbers are worked out here.
        if let plan = RoutinePlans.plan(for: part) {
            let doneToday = Set(records.filter { calendar.isDate($0.date, inSameDayAs: now) }.map(\.exercise))
            return plan.map { item in
                let next = progression(for: item.name, muscle: Muscle.lookup(item.name, in: profiles),
                                       records: records, unit: unit, progresses: progresses, doneToday: doneToday)
                return RoutineSuggestion(exercise: next.exercise, muscle: next.muscle, weight: next.weight, reps: next.reps,
                                         sets: item.sets, note: next.note, isNew: next.isNew, doneToday: next.doneToday)
            }
        }
        let muscles = muscles(in: part)
        let since = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let recent = records.filter { $0.date >= since && !$0.exercise.isEmpty }
        let doneToday = Set(records.filter { calendar.isDate($0.date, inSameDayAs: now) }.map(\.exercise))

        // Frequency score per exercise; lifts done on this part's days count extra.
        var score: [String: Int] = [:]
        for record in recent { score[record.exercise, default: 0] += record.routineName == part ? 3 : 1 }
        // Starter lifts the user already logs under another spelling ("덤벨프레스" vs "덤벨 프레스") are skipped.
        let known = Set(records.map { ExerciseLibrary.normalized($0.exercise) })

        var queues: [[RoutineSuggestion]]
        if muscles.isEmpty {
            // A custom part name: fall back to whatever was done on that part's days.
            let names = Set(recent.filter { $0.routineName == part }.map(\.exercise))
            queues = [names.sorted { score[$0, default: 0] > score[$1, default: 0] }
                .map {
                    progression(for: $0, muscle: Muscle.lookup($0, in: profiles), records: records, unit: unit,
                                progresses: progresses, doneToday: doneToday)
                }]
        } else {
            queues = muscles.map { muscle in
                let own = Set(recent.map(\.exercise))
                    .filter { Muscle.lookup($0, in: profiles) == muscle }
                    .sorted { score[$0, default: 0] > score[$1, default: 0] }
                let ownSuggestions = own.map {
                    progression(for: $0, muscle: muscle, records: records, unit: unit, progresses: progresses, doneToday: doneToday)
                }
                let starters = library(for: muscle)
                    .filter { name, _ in !known.contains(ExerciseLibrary.normalized(name)) }
                    .map { name, weight in
                        RoutineSuggestion(exercise: name, muscle: muscle, weight: weight, reps: 10, sets: 3,
                                          note: String(localized: "처음이면 가볍게 시작해요"), isNew: true,
                                          doneToday: doneToday.contains(name))
                    }
                return ownSuggestions + starters
            }
        }

        let total = switch muscles.count { case 0, 1: 4; case 2: 5; default: 6 }
        var result: [RoutineSuggestion] = []
        var round = 0
        while result.count < total, queues.contains(where: { round < $0.count }) {
            for queue in queues where round < queue.count && result.count < total {
                result.append(queue[round])
            }
            round += 1
        }
        return result
    }

    /// Next target from the latest session: 12+ reps on the top weight → add weight and
    /// drop to 8 reps; 8+ reps → one more rep; fewer → repeat the same numbers.
    private static func progression(for exercise: String, muscle: Muscle, records: [WorkoutRecord],
                                    unit: WeightUnit, progresses: Bool, doneToday: Set<String>) -> RoutineSuggestion {
        guard let last = records.first(where: { $0.exercise == exercise }) else {
            return RoutineSuggestion(exercise: exercise, muscle: muscle, weight: ExerciseLibrary.find(exercise)?.startWeight ?? 0,
                                     reps: 10, sets: 3, note: String(localized: "처음이면 가볍게 시작해요"),
                                     isNew: true, doneToday: doneToday.contains(exercise))
        }
        let values = last.setValues
        let top = values.map(\.weight).max() ?? last.weight
        let reps = values.filter { $0.weight == top }.map(\.reps).min() ?? last.reps
        let sets = max(values.count, 3)
        // One plate step in the display unit: 2.5kg or 5lb.
        let step = unit == .kg ? 2.5 : unit.toKg(5)

        let weight: Double, nextReps: Int, note: String
        if !progresses {
            (weight, nextReps, note) = (top, max(reps, 1), "")
        } else if top == 0 {
            (weight, nextReps, note) = (0, reps + (reps >= 12 ? 2 : 1), String(localized: "지난번보다 한두 개 더"))
        } else if reps >= 12 {
            (weight, nextReps, note) = (top + step, 8, String(localized: "+\(formatMass(step, unit: unit)) 올려볼 때예요"))
        } else if reps >= 8 {
            (weight, nextReps, note) = (top, reps + 1, String(localized: "같은 무게로 1회 더"))
        } else {
            (weight, nextReps, note) = (top, max(reps, 1), String(localized: "지난번 무게 그대로"))
        }
        return RoutineSuggestion(exercise: exercise, muscle: muscle, weight: weight, reps: nextReps, sets: sets,
                                 note: note, isNew: false, doneToday: doneToday.contains(exercise))
    }
}
