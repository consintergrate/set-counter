import SwiftData
import SwiftUI

/// Everything done on one day: strength sets, other apps' workouts, activity,
/// food against the target, and weight. Steps back through the past four weeks.
struct DailyReportView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Environment(\.dismiss) private var dismiss

    @State private var dayOffset = 0

    private let health = HealthData.shared
    private var calendar: Calendar { .current }
    /// Health's daily totals cover four weeks.
    private let oldestOffset = -27

    private var day: Date {
        calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        let day = day
        let goals = Goals.saved
        let dayRecords = records.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
        let workouts = health.cardio.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let personalBests = bests(on: day, in: dayRecords)

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PeriodSwitcher(
                        title: day.formatted(.dateTime.month(.wide).day().weekday(.wide)),
                        subtitle: dayOffset == 0 ? String(localized: "오늘") : dayOffset == -1 ? String(localized: "어제") : nil,
                        canGoBack: dayOffset > oldestOffset,
                        canGoForward: dayOffset < 0,
                        onBack: { dayOffset -= 1 },
                        onForward: { dayOffset += 1 }
                    )

                    ReportCard(title: "한 줄 요약", systemImage: "text.bubble.fill", color: .accentColor) {
                        SummaryLines(lines: summary(dayRecords: dayRecords, workouts: workouts, bests: personalBests, goals: goals))
                    }

                    activityTiles(goals: goals)
                    strengthCard(dayRecords, bests: personalBests)
                    if !workouts.isEmpty {
                        ReportCard(title: "다른 앱 운동", systemImage: "figure.run", color: .teal) {
                            ForEach(workouts) { CardioRow(workout: $0) }
                        }
                    }
                    mealCard
                    calorieCard(goals: goals)
                    weightCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("하루 리포트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
            .task { await health.refresh() }
        }
    }

    // MARK: Sections

    private func activityTiles(goals: Goals) -> some View {
        let steps = health.dailySteps[day]
        let active = health.dailyActive[day]
        let minutes = health.exerciseMinutes(on: day, records: records)
        let eaten = health.dailyEaten[day]
        let target = goals.intakeTarget(profile: .saved)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ReportTile(title: "활동 칼로리", value: active.map { "\(Int($0).formatted())kcal" } ?? "–",
                       detail: String(localized: "목표 \(goals.activeCalories.formatted())kcal"),
                       progress: active.map { $0 / Double(max(goals.activeCalories, 1)) }, color: .pink)
            ReportTile(title: "걸음", value: steps.map { Int($0).formatted() } ?? "–",
                       detail: String(localized: "목표 \(goals.steps.formatted())보"),
                       progress: steps.map { $0 / Double(max(goals.steps, 1)) }, color: .cyan)
            ReportTile(title: "운동 시간", value: String(localized: "\(Int(minutes))분"),
                       detail: String(localized: "목표 \(goals.exerciseMinutes)분"),
                       progress: minutes / Double(max(goals.exerciseMinutes, 1)), color: .green)
            ReportTile(title: "먹은 칼로리", value: eaten.map { "\(Int($0).formatted())kcal" } ?? "–",
                       detail: String(localized: "목표 \(Int(target + (active ?? 0)).formatted())kcal"),
                       progress: eaten.map { $0 / max(target + (active ?? 0), 1) }, color: .orange, goalIsLimit: true)
        }
    }

    @ViewBuilder
    private func strengthCard(_ dayRecords: [WorkoutRecord], bests: [(name: String, value: String)]) -> some View {
        ReportCard(title: "근력 운동", systemImage: "dumbbell.fill", color: .orange) {
            if dayRecords.isEmpty {
                Text("이 날은 근력 운동 기록이 없어요.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    MiniStat(title: "운동", value: String(localized: "\(Set(dayRecords.map(\.exercise)).count)개"))
                    MiniStat(title: "세트", value: String(localized: "\(dayRecords.reduce(0) { $0 + $1.sets })세트"))
                    MiniStat(title: "볼륨", value: formatMass(dayRecords.reduce(0) { $0 + $1.volume }))
                    MiniStat(title: "시간", value: formatClock(dayRecords.reduce(0) { $0 + $1.duration }))
                }
                ForEach(dayRecords) { record in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.exercise.isEmpty ? String(localized: "운동") : record.exercise).font(.subheadline.bold())
                            Text(setsSummary(record.setValues)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        if record.calories > 0 {
                            Text("\(Int(record.calories).formatted())kcal").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 2)
                }
                ForEach(bests, id: \.name) { item in
                    Label("\(item.name) 신기록 \(item.value)", systemImage: "trophy.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func calorieCard(goals: Goals) -> some View {
        let breakdown = goals.intakeBreakdown(profile: .saved)
        let eaten = health.dailyEaten[day] ?? 0
        let burned = health.dailyActive[day] ?? 0
        let remaining = breakdown.target - eaten + burned
        return ReportCard(title: "칼로리", systemImage: "flame.fill", color: .red) {
            VStack(spacing: 8) {
                row("기초대사량 (BMR)", breakdown.bmr)
                row("기본 목표", breakdown.target)
                row("먹은 칼로리", eaten, sign: "−")
                row("활동 칼로리 (건강 앱)", burned, sign: "+")
                Divider()
                HStack {
                    Text(remaining >= 0 ? "남은 칼로리" : "초과한 칼로리").font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(abs(remaining)).formatted())kcal")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(remaining >= 0 ? Color.primary : Color.red)
                }
            }
            if health.dailyEaten[day] == nil {
                Text("이 날은 식사 기록이 없어요. 홈의 '식사 추가'로 기록하면 더 정확해져요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mealCard: some View {
        let meals = health.meals(on: day)
        return ReportCard(title: "식사", systemImage: "fork.knife", color: .orange) {
            if meals.isEmpty {
                Text("이 날은 기록한 식사가 없어요.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(meals) { MealRow(meal: $0) }
        }
    }

    @ViewBuilder
    private var weightCard: some View {
        let entries = health.weights.filter { calendar.isDate($0.date, inSameDayAs: day) }
        if !entries.isEmpty {
            ReportCard(title: "체중", systemImage: "scalemass.fill", color: .blue) {
                ForEach(entries) { entry in
                    LabeledContent(entry.date.formatted(date: .omitted, time: .shortened)) {
                        Text(formatMass(entry.kg)).bold().monospacedDigit()
                    }
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Double, sign: String = "") -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text("\(sign)\(Int(value.rounded()).formatted())kcal").font(.subheadline).monospacedDigit()
        }
    }

    // MARK: Data

    /// Exercises where this day beat everything before it.
    private func bests(on day: Date, in dayRecords: [WorkoutRecord]) -> [(name: String, value: String)] {
        let before = records.filter { $0.date < day }
        return Set(dayRecords.map(\.exercise)).filter { !$0.isEmpty }.sorted().compactMap { name in
            guard let now = PersonalBest.of(name, in: dayRecords), let old = PersonalBest.of(name, in: before) else { return nil }
            if now.weight > 0, now.weight > old.weight { return (name, formatWeight(now.weight)) }
            if now.weight == 0, now.reps > old.reps { return (name, String(localized: "\(now.reps)회")) }
            return nil
        }
    }

    private func summary(dayRecords: [WorkoutRecord], workouts: [CardioWorkout], bests: [(name: String, value: String)],
                         goals: Goals) -> [String] {
        var lines: [String] = []
        if dayRecords.isEmpty {
            lines.append(String(localized: "💪 근력 운동은 쉬었어요."))
        } else {
            let sets = dayRecords.reduce(0) { $0 + $1.sets }
            let part = dayRecords.first(where: { !$0.routineName.isEmpty })?.routineName
            lines.append(part.map { String(localized: "💪 \($0) 운동 \(Set(dayRecords.map(\.exercise)).count)개, \(sets)세트를 했어요.") }
                ?? String(localized: "💪 근력 운동 \(sets)세트를 했어요."))
        }
        for workout in workouts.prefix(2) {
            lines.append("\(workout.isCardio ? "🏃" : "🏋️") \(workout.title) \(workout.summary)")
        }
        if let steps = health.dailySteps[day] {
            let count = Int(steps)
            lines.append(count >= goals.steps
                ? String(localized: "👟 \(count.formatted())보, 걸음 목표를 채웠어요.")
                : String(localized: "👟 \(count.formatted())보, 목표까지 \((goals.steps - count).formatted())보 남았어요."))
        }
        if let eaten = health.dailyEaten[day] {
            let allowance = Int(goals.intakeTarget(profile: .saved) + (health.dailyActive[day] ?? 0))
            let eatenInt = Int(eaten)
            lines.append(eatenInt <= allowance
                ? String(localized: "🥗 \(eatenInt.formatted())kcal 먹고 \((allowance - eatenInt).formatted())kcal 남겼어요.")
                : String(localized: "🍔 \(eatenInt.formatted())kcal 먹어서 \((eatenInt - allowance).formatted())kcal 넘었어요."))
        }
        for best in bests {
            lines.append(String(localized: "🏆 \(best.name) 신기록 \(best.value)!"))
        }
        return lines
    }
}
