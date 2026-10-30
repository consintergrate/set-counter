import SwiftData
import SwiftUI

/// One week of strength, cardio, activity, food, and weight, compared with the week before.
struct WeeklyReportView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Query private var profiles: [ExerciseProfile]
    @AppStorage("weeklyGoal") private var weeklyGoal = 4
    @Environment(\.dismiss) private var dismiss

    /// On a week's first day there's little to show yet, so open on the week just finished.
    @State private var weekOffset = Self.defaultOffset
    @State private var paywall: ProFeature?

    /// The week the report opens on, also the oldest one without Pro.
    private static var defaultOffset: Int {
        Calendar.current.component(.weekday, from: Date()) == Calendar.current.firstWeekday ? -1 : 0
    }

    private let health = HealthData.shared
    private let store = ProStore.shared
    private var calendar: Calendar { .current }
    private let oldestOffset = -11

    struct Stats {
        var strengthDays: Set<Date> = []
        var cardioDays: Set<Date> = []
        var sets = 0
        var volume: Double = 0
        var strengthTime: TimeInterval = 0
        var cardio: [CardioWorkout] = []
        var cardioMinutes = 0
        var cardioDistance: Double = 0
        var dailyActive: [Date: Double] = [:]
        var averageSteps: Int?
        var averageActive: Int?
        var averageEaten: Int?
        var eatenDays = 0
        var weightStart: Double?
        var weightEnd: Double?
        var records: [(name: String, value: String)] = []
        var muscleSets: [Muscle: Int] = [:]

        var weightChange: Double? {
            guard let weightStart, let weightEnd else { return nil }
            return weightEnd - weightStart
        }
    }

    private func interval(offset: Int) -> DateInterval? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()),
              let start = calendar.date(byAdding: .weekOfYear, value: offset, to: week.start),
              let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func stats(for week: DateInterval) -> Stats {
        var stats = Stats()
        let inWeek = records.filter { $0.date >= week.start && $0.date < week.end }
        stats.strengthDays = Set(inWeek.map { calendar.startOfDay(for: $0.date) })
        stats.sets = inWeek.reduce(0) { $0 + $1.sets }
        stats.volume = inWeek.reduce(0) { $0 + $1.volume }
        stats.strengthTime = inWeek.reduce(0) { $0 + $1.duration }
        for record in inWeek where !record.exercise.isEmpty {
            stats.muscleSets[Muscle.lookup(record.exercise, in: profiles), default: 0] += record.sets
        }

        // A record for the week: better than anything before the week started.
        let before = records.filter { $0.date < week.start }
        for name in Set(inWeek.map(\.exercise)).filter({ !$0.isEmpty }).sorted() {
            guard let now = PersonalBest.of(name, in: inWeek) else { continue }
            let old = PersonalBest.of(name, in: before)
            if now.weight > 0, now.weight > old?.weight ?? 0 {
                stats.records.append((name, formatWeight(now.weight)))
            } else if now.weight == 0, now.reps > old?.reps ?? 0 {
                stats.records.append((name, String(localized: "\(now.reps)회")))
            }
        }

        let workouts = health.cardio.filter { $0.start >= week.start && $0.start < week.end }
        // Other apps' strength workouts (an Apple Watch "근력 운동") count as strength days.
        stats.strengthDays.formUnion(workouts.filter { !$0.isCardio }.map { calendar.startOfDay(for: $0.start) })
        stats.cardio = workouts.filter(\.isCardio).sorted { $0.start < $1.start }
        stats.cardioDays = Set(stats.cardio.map { calendar.startOfDay(for: $0.start) })
        stats.cardioMinutes = Int(stats.cardio.reduce(0) { $0 + $1.duration } / 60)
        stats.cardioDistance = stats.cardio.reduce(0) { $0 + $1.distance }

        // Averages over the days that have passed, so a half-finished week isn't diluted.
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }.filter { $0 <= Date() }
        for day in days { stats.dailyActive[day] = health.dailyActive[day] }
        func average(_ values: [Date: Double], loggedOnly: Bool = false) -> Int? {
            let found = days.compactMap { values[$0] }.filter { !loggedOnly || $0 > 0 }
            guard !found.isEmpty else { return nil }
            return Int(found.reduce(0, +) / Double(loggedOnly ? found.count : days.count))
        }
        stats.averageSteps = average(health.dailySteps)
        stats.averageActive = average(health.dailyActive)
        stats.averageEaten = average(health.dailyEaten, loggedOnly: true)
        stats.eatenDays = days.filter { (health.dailyEaten[$0] ?? 0) > 0 }.count

        let weights = health.weights.filter { $0.date >= week.start && $0.date < week.end }
        if let first = weights.first, let last = weights.last, first.date != last.date {
            stats.weightStart = first.kg
            stats.weightEnd = last.kg
        }
        return stats
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let week = interval(offset: weekOffset), let previousWeek = interval(offset: weekOffset - 1) {
                    report(week: week, stats: stats(for: week), previous: stats(for: previousWeek))
                        .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("주간 리포트")
            .proPaywall($paywall)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
            .task { await health.refresh() }
        }
    }

    private func report(week: DateInterval, stats: Stats, previous: Stats) -> some View {
        let goals = Goals.saved
        // What could be eaten on an average day: base target plus average activity.
        let target = Int(goals.intakeTarget(profile: .saved)) + (stats.averageActive ?? 0)
        let end = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end
        return VStack(spacing: 14) {
            PeriodSwitcher(
                title: "\(week.start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))",
                subtitle: weekOffset == 0 ? String(localized: "이번 주") : weekOffset == -1 ? String(localized: "지난주") : nil,
                canGoBack: weekOffset > oldestOffset,
                canGoForward: weekOffset < 0,
                backIsLocked: !store.isPro && weekOffset <= Self.defaultOffset,
                onBack: {
                    if store.isPro || weekOffset > Self.defaultOffset { weekOffset -= 1 } else { paywall = .reports }
                },
                onForward: { weekOffset += 1 }
            )

            ReportCard(title: "한 줄 요약", systemImage: "text.bubble.fill", color: .accentColor) {
                SummaryLines(lines: summaryLines(stats, goals: goals, target: target))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ReportTile(title: "운동한 날", value: String(localized: "\(stats.strengthDays.count)/\(weeklyGoal)일"),
                           progress: Double(stats.strengthDays.count) / Double(max(weeklyGoal, 1)), color: .orange,
                           delta: delta(stats.strengthDays.count, previous.strengthDays.count) { String(localized: "\($0)일") })
                ReportTile(title: "유산소", value: String(localized: "\(stats.cardioMinutes)분"),
                           detail: String(localized: "목표 \(goals.cardioWeeklyMinutes)분"),
                           progress: Double(stats.cardioMinutes) / Double(max(goals.cardioWeeklyMinutes, 1)), color: .teal,
                           delta: delta(stats.cardioMinutes, previous.cardioMinutes) { String(localized: "\($0)분") })
                ReportTile(title: "평균 걸음", value: stats.averageSteps.map { $0.formatted() } ?? "–",
                           detail: String(localized: "목표 \(goals.steps.formatted())보"),
                           progress: stats.averageSteps.map { Double($0) / Double(max(goals.steps, 1)) }, color: .cyan,
                           delta: delta(stats.averageSteps, previous.averageSteps) { String(localized: "\($0.formatted())보") })
                ReportTile(title: "하루 평균 섭취", value: stats.averageEaten.map { "\($0.formatted())kcal" } ?? "–",
                           detail: String(localized: "목표 \(target.formatted())kcal"),
                           progress: stats.averageEaten.map { Double($0) / Double(max(target, 1)) }, color: .orange,
                           goalIsLimit: true,
                           delta: delta(stats.averageEaten, previous.averageEaten, upIsGood: false) { "\($0.formatted())kcal" })
            }

            if !store.isPro {
                Button {
                    paywall = .reports
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").foregroundStyle(Color.orange.readable)
                        Text("지난주와 비교해 보기")
                        Spacer()
                        ProBadge()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            dayStrip(stats, week: week)

            ReportCard(title: "근력 운동", systemImage: "dumbbell.fill", color: .orange) {
                HStack(spacing: 0) {
                    MiniStat(title: "세트", value: String(localized: "\(stats.sets)세트"))
                    MiniStat(title: "볼륨", value: formatMass(stats.volume))
                    MiniStat(title: "시간", value: formatClock(stats.strengthTime))
                }
                if stats.muscleSets.isEmpty {
                    Text("이 주에는 근력 운동 기록이 없어요.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    MuscleBars(sets: stats.muscleSets)
                    Text("부위마다 주 10세트 이상이면 초록색이에요.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(stats.records, id: \.name) { item in
                    Label("\(item.name) \(item.value)", systemImage: "trophy.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.orange.readable)
                }
            }

            ReportCard(title: "유산소", systemImage: "figure.run", color: .teal) {
                HStack(spacing: 0) {
                    MiniStat(title: "시간", value: String(localized: "\(stats.cardioMinutes)분"))
                    MiniStat(title: "거리", value: formatDistance(stats.cardioDistance))
                    MiniStat(title: "횟수", value: String(localized: "cardio.sessions", defaultValue: "\(stats.cardio.count)회"))
                }
                if stats.cardio.isEmpty {
                    Text("나이키 런 클럽, 피트니스 등에서 건강 앱에 저장한 운동이 여기에 모여요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(stats.cardio) { workout in
                    HStack(spacing: 10) {
                        Image(systemName: workout.systemImage).foregroundStyle(.teal).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(workout.title) · \(workout.summary)").font(.subheadline.bold()).monospacedDigit()
                            Text("\(workout.start.formatted(.dateTime.weekday(.wide))) · \(workout.source)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ReportCard(title: "식단 · 체중", systemImage: "fork.knife", color: .green) {
                LabeledContent("하루 평균 섭취") {
                    Text(stats.averageEaten.map { "\($0.formatted()) / \(target.formatted())kcal" } ?? "–").bold().monospacedDigit()
                }
                LabeledContent("식사 기록한 날") {
                    Text(String(localized: "\(stats.eatenDays)일")).bold().monospacedDigit()
                }
                LabeledContent("평균 활동 칼로리") {
                    Text(stats.averageActive.map { "\($0.formatted())kcal" } ?? "–").bold().monospacedDigit()
                }
                LabeledContent("체중") {
                    if let start = stats.weightStart, let end = stats.weightEnd {
                        Text("\(formatMass(start)) → \(formatMass(end))").bold().monospacedDigit()
                    } else {
                        Text("–")
                    }
                }
                Text("평균 섭취는 식사를 기록한 날만 계산해요.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Active calories per day as bars, with a dumbbell on strength days and a
    /// runner on cardio days.
    private func dayStrip(_ stats: Stats, week: DateInterval) -> some View {
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
        let top = max(stats.dailyActive.values.max() ?? 0, 1)
        return ReportCard(title: "요일별 활동", systemImage: "calendar", color: .pink) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let active = stats.dailyActive[day] ?? 0
                    VStack(spacing: 5) {
                        Text(active > 0 ? "\(Int(active))" : " ")
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day > Date() ? Color.secondary.opacity(0.08) : Color.pink.opacity(active > 0 ? 0.8 : 0.15))
                            .frame(height: max(100 * active / top, 4))
                        HStack(spacing: 1) {
                            if stats.strengthDays.contains(day) {
                                Image(systemName: "dumbbell.fill").foregroundStyle(.orange)
                            }
                            if stats.cardioDays.contains(day) {
                                Image(systemName: "figure.run").foregroundStyle(.teal)
                            }
                        }
                        .font(.system(size: 9))
                        .frame(height: 12)
                        Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: day) - 1])
                            .font(.caption2.weight(calendar.isDateInToday(day) ? .bold : .regular))
                            .foregroundStyle(calendar.isDateInToday(day) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 160, alignment: .bottom)
            HStack(spacing: 12) {
                Label("활동 칼로리", systemImage: "circle.fill").foregroundStyle(Color.pink.readable)
                Label("근력", systemImage: "circle.fill").foregroundStyle(Color.orange.readable)
                Label("유산소", systemImage: "circle.fill").foregroundStyle(Color.teal.readable)
            }
            .labelStyle(LegendLabelStyle())
            .font(.caption)
        }
    }

    private func delta(_ value: Int?, _ previous: Int?, upIsGood: Bool = true, format: (Int) -> String) -> ReportTile.Delta? {
        // Comparing with the week before is Pro.
        guard store.isPro, let value, let previous, value != previous else { return nil }
        return ReportTile.Delta(text: format(abs(value - previous)), isUp: value > previous, upIsGood: upIsGood)
    }

    /// Plain-language verdicts on the week.
    private func summaryLines(_ stats: Stats, goals: Goals, target: Int) -> [String] {
        var lines: [String] = []
        let days = stats.strengthDays.count
        lines.append(days >= weeklyGoal
            ? String(localized: "💪 근력 운동 목표 \(weeklyGoal)일을 채웠어요.")
            : String(localized: "💪 근력 운동 \(days)일, 목표까지 \(weeklyGoal - days)일 모자라요."))
        if goals.cardioWeeklyMinutes > 0 {
            lines.append(stats.cardioMinutes >= goals.cardioWeeklyMinutes
                ? String(localized: "🏃 유산소 \(stats.cardioMinutes)분으로 목표를 넘겼어요.")
                : String(localized: "🏃 유산소 \(stats.cardioMinutes)분, 목표의 \(stats.cardioMinutes * 100 / goals.cardioWeeklyMinutes)%예요."))
        }
        if let eaten = stats.averageEaten {
            lines.append(eaten <= target
                ? String(localized: "🥗 하루 평균 \(eaten.formatted())kcal로 목표 안에서 먹었어요.")
                : String(localized: "🍔 하루 평균 \(eaten.formatted())kcal, 목표보다 \((eaten - target).formatted())kcal 많아요."))
        }
        if let change = stats.weightChange {
            lines.append(change <= 0
                ? String(localized: "⚖️ 체중이 \(formatMass(-change)) 줄었어요.")
                : String(localized: "⚖️ 체중이 \(formatMass(change)) 늘었어요."))
        }
        if !stats.records.isEmpty {
            lines.append(String(localized: "🏆 신기록 \(stats.records.count)개!"))
        }
        return lines
    }
}
