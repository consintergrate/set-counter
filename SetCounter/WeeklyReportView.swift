import SwiftData
import SwiftUI

/// One week of strength, cardio, activity, food, and weight, compared with the week before.
struct WeeklyReportView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Query private var profiles: [ExerciseProfile]
    @AppStorage("weeklyGoal") private var weeklyGoal = 4
    @Environment(\.dismiss) private var dismiss

    /// On a week's first day there's little to show yet, so open on the week just finished.
    @State private var weekOffset = Calendar.current.component(.weekday, from: Date()) == Calendar.current.firstWeekday ? -1 : 0

    private let health = HealthData.shared
    private var calendar: Calendar { .current }

    struct Stats {
        var strengthDays = 0
        var sets = 0
        var volume: Double = 0
        var cardioMinutes = 0
        var cardioDistance: Double = 0
        var cardioCount = 0
        var averageSteps: Int?
        var averageActive: Int?
        var averageEaten: Int?
        var weightChange: Double?
        var records: [(name: String, value: String)] = []
        var muscleSets: [Muscle: Int] = [:]
    }

    private func interval(offset: Int) -> DateInterval? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()),
              let start = calendar.date(byAdding: .weekOfYear, value: offset, to: week.start),
              let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func stats(for week: DateInterval) -> Stats {
        var stats = Stats()
        let inWeek = records.filter { week.contains($0.date) && $0.date < week.end }
        stats.strengthDays = Set(inWeek.map { calendar.startOfDay(for: $0.date) }).count
        stats.sets = inWeek.reduce(0) { $0 + $1.sets }
        stats.volume = inWeek.reduce(0) { $0 + $1.volume }
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

        let cardio = health.cardio.filter { week.contains($0.start) && $0.start < week.end && $0.isCardio }
        stats.cardioMinutes = Int(cardio.reduce(0) { $0 + $1.duration } / 60)
        stats.cardioDistance = cardio.reduce(0) { $0 + $1.distance }
        stats.cardioCount = cardio.count

        // Averages over the days that have passed, so a half-finished week isn't diluted.
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }.filter { $0 <= Date() }
        func average(_ values: [Date: Double], skipEmpty: Bool = false) -> Int? {
            let found = days.compactMap { values[$0] }.filter { !skipEmpty || $0 > 0 }
            guard !found.isEmpty else { return nil }
            return Int(found.reduce(0, +) / Double(skipEmpty ? found.count : days.count))
        }
        stats.averageSteps = average(health.dailySteps)
        stats.averageActive = average(health.dailyActive)
        stats.averageEaten = average(health.dailyEaten, skipEmpty: true)

        let weights = health.weights.filter { week.contains($0.date) && $0.date < week.end }
        if let first = weights.first, let last = weights.last, first.date != last.date {
            stats.weightChange = last.kg - first.kg
        }
        return stats
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("주", selection: $weekOffset) {
                    Text("이번 주").tag(0)
                    Text("지난주").tag(-1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let week = interval(offset: weekOffset), let previous = interval(offset: weekOffset - 1) {
                    report(stats(for: week), previous: stats(for: previous), week: week)
                }
            }
            .navigationTitle("주간 리포트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
            .task { await health.refresh() }
        }
    }

    @ViewBuilder
    private func report(_ stats: Stats, previous: Stats, week: DateInterval) -> some View {
        let goals = Goals.saved
        let end = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end

        Section {
            Text("\(week.start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(summaryLines(stats, goals: goals), id: \.self) { line in
                Text(line).font(.subheadline)
            }
        } header: {
            Text("한 줄 요약")
        }

        Section("근력 운동") {
            row("운동한 날", String(localized: "\(stats.strengthDays)/\(weeklyGoal)일"), delta: stats.strengthDays - previous.strengthDays) { String(localized: "\($0)일") }
            row("세트", String(localized: "\(stats.sets)세트"), delta: stats.sets - previous.sets) { String(localized: "\($0)세트") }
            row("총 볼륨", formatMass(stats.volume))
            ForEach(stats.records, id: \.name) { item in
                Label("\(item.name) \(item.value)", systemImage: "trophy.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            let muscles = Muscle.tracked.filter { stats.muscleSets[$0, default: 0] > 0 }
            if !muscles.isEmpty {
                Text(muscles.map { "\($0.title) \(stats.muscleSets[$0, default: 0])" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("유산소") {
            row("시간", String(localized: "\(stats.cardioMinutes)/\(goals.cardioWeeklyMinutes)분"), delta: stats.cardioMinutes - previous.cardioMinutes) { String(localized: "\($0)분") }
            row("거리", formatDistance(stats.cardioDistance))
            row("횟수", cardioSessions(stats.cardioCount), delta: stats.cardioCount - previous.cardioCount, format: cardioSessions)
        }

        Section {
            row("평균 걸음", stats.averageSteps.map { String(localized: "\($0.formatted())보") } ?? "–",
                delta: zip(stats.averageSteps, previous.averageSteps).map { $0 - $1 }) { String(localized: "\($0.formatted())보") }
            row("평균 활동 칼로리", stats.averageActive.map { "\($0.formatted())kcal" } ?? "–",
                delta: zip(stats.averageActive, previous.averageActive).map { $0 - $1 }) { "\($0.formatted())kcal" }
            row("평균 섭취", stats.averageEaten.map { "\($0.formatted())kcal" } ?? "–")
            row("체중 변화", stats.weightChange.map { ($0 > 0 ? "+" : "") + formatMass($0) } ?? "–")
        } header: {
            Text("활동 · 식단")
        } footer: {
            Text("하루 권장 섭취는 \(Int(goals.intakeTarget(profile: .saved)).formatted())kcal예요. 섭취 평균은 기록한 날만 계산해요.")
        }
    }

    private func zip(_ a: Int?, _ b: Int?) -> (Int, Int)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    /// Its own key: "%lld회" alone reads as reps in English.
    private func cardioSessions(_ count: Int) -> String {
        String(localized: "cardio.sessions", defaultValue: "\(count)회")
    }

    /// A stat with, optionally, the change from the week before formatted by `format`.
    private func row(_ title: LocalizedStringKey, _ value: String, delta: Int? = nil,
                     format: (Int) -> String = { "\($0)" }) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(value).bold().monospacedDigit().foregroundStyle(.primary)
                if let delta, delta != 0 {
                    Text("\(delta > 0 ? "▲" : "▼")\(format(abs(delta)))")
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(delta > 0 ? .green : .orange)
                }
            }
        }
    }

    /// Plain-language verdicts on the week.
    private func summaryLines(_ stats: Stats, goals: Goals) -> [String] {
        var lines: [String] = []
        lines.append(stats.strengthDays >= weeklyGoal
            ? String(localized: "💪 근력 운동 목표 \(weeklyGoal)일을 채웠어요.")
            : String(localized: "💪 근력 운동 \(stats.strengthDays)일, 목표까지 \(weeklyGoal - stats.strengthDays)일 모자라요."))
        if goals.cardioWeeklyMinutes > 0 {
            lines.append(stats.cardioMinutes >= goals.cardioWeeklyMinutes
                ? String(localized: "🏃 유산소 \(stats.cardioMinutes)분으로 목표를 넘겼어요.")
                : String(localized: "🏃 유산소 \(stats.cardioMinutes)분, 목표의 \(stats.cardioMinutes * 100 / goals.cardioWeeklyMinutes)%예요."))
        }
        if let eaten = stats.averageEaten {
            let target = Int(goals.intakeTarget(profile: .saved))
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
