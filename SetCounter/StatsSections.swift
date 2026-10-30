import Charts
import SwiftData
import SwiftUI

// MARK: - Activity heatmap and streaks

/// A year of workout days as a GitHub-style grid, with week streaks above it.
struct ActivityHeatmap: View {
    let records: [WorkoutRecord]
    let weeklyGoal: Int

    @State private var selectedDay: Date?

    private static let weeksShown = 53
    private var calendar: Calendar { .current }

    private var setsByDay: [Date: Int] {
        Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.sets } }
    }

    private var thisWeek: Date {
        calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
    }

    /// Columns of seven days each, oldest first; the last column is this week.
    private var columns: [[Date]] {
        (0..<Self.weeksShown).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        }
    }

    private var daysByWeek: [Date: Int] {
        Dictionary(grouping: Set(records.map { calendar.startOfDay(for: $0.date) })) {
            calendar.dateInterval(of: .weekOfYear, for: $0)?.start ?? $0
        }
        .mapValues(\.count)
    }

    /// Consecutive weeks counting back from the latest one that qualifies. The current
    /// week may still be in progress, so if it doesn't qualify yet the count starts last week.
    private func streak(_ qualifies: (Int) -> Bool) -> Int {
        let weeks = daysByWeek
        var week = thisWeek
        if !qualifies(weeks[week] ?? 0) {
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        }
        var count = 0
        while qualifies(weeks[week] ?? 0) {
            count += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return count
    }

    private var longestWeekStreak: Int {
        let weeks = daysByWeek.keys.sorted()
        var best = 0, run = 0
        var previous: Date?
        for week in weeks {
            if let previous, calendar.date(byAdding: .weekOfYear, value: 1, to: previous) == week {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = week
        }
        return best
    }

    private var daysThisYear: Int {
        Set(records.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .year) }
            .map { calendar.startOfDay(for: $0.date) }).count
    }

    private static func level(_ sets: Int) -> Int {
        switch sets {
        case 0: 0
        case 1...5: 1
        case 6...12: 2
        case 13...20: 3
        default: 4
        }
    }

    private static func fill(_ level: Int) -> AnyShapeStyle {
        let opacity = [0.0, 0.3, 0.52, 0.75, 1.0][level]
        return level == 0 ? AnyShapeStyle(Color.secondary.opacity(0.14)) : AnyShapeStyle(.tint.opacity(opacity))
    }

    var body: some View {
        let sets = setsByDay
        let today = calendar.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MiniStat(title: "연속 운동 주", value: String(localized: "\(streak { $0 > 0 })주"))
                MiniStat(title: "목표 달성 연속", value: String(localized: "\(streak { $0 >= weeklyGoal })주"))
                MiniStat(title: "최장 연속", value: String(localized: "\(longestWeekStreak)주"))
                MiniStat(title: "올해 운동일", value: String(localized: "\(daysThisYear)일"))
            }

            Group {
                if let selectedDay {
                    Text("\(selectedDay.formatted(date: .abbreviated, time: .omitted)) · \(sets[selectedDay] ?? 0)세트")
                } else {
                    Text("최근 1년 \(sets.keys.filter { $0 > calendar.date(byAdding: .year, value: -1, to: today) ?? today }.count)일 운동 · 칸을 누르면 그날 세트 수가 보여요")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(columns, id: \.first) { week in
                        VStack(spacing: 3) {
                            monthLabel(for: week)
                            ForEach(week, id: \.self) { day in
                                let isFuture = day > today
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(isFuture ? AnyShapeStyle(Color.clear) : Self.fill(Self.level(sets[day] ?? 0)))
                                    .frame(width: 12, height: 12)
                                    .overlay {
                                        if day == selectedDay {
                                            RoundedRectangle(cornerRadius: 2.5).stroke(Color.primary, lineWidth: 1.5)
                                        }
                                    }
                                    .contentShape(Rectangle().inset(by: -1.5))
                                    .onTapGesture {
                                        guard !isFuture else { return }
                                        selectedDay = selectedDay == day ? nil : day
                                    }
                                    .accessibilityLabel(Text("\(day.formatted(date: .abbreviated, time: .omitted)) \(sets[day] ?? 0)세트"))
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)

            HStack(spacing: 4) {
                Spacer()
                Text("적음").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5).fill(Self.fill(level)).frame(width: 12, height: 12)
                }
                Text("많음").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Month name over the first column that contains the 1st of a month.
    private func monthLabel(for week: [Date]) -> some View {
        let firstOfMonth = week.first { calendar.component(.day, from: $0) == 1 }
        return Text(firstOfMonth.map { $0.formatted(.dateTime.month(.abbreviated)) } ?? " ")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(width: 12, height: 12, alignment: .leading)
    }
}

// MARK: - Weekly muscle balance

/// The last 7 days' sets per body part against the common 10–20 sets/week guideline.
struct BalanceChart: View {
    let records: [WorkoutRecord]

    @Query private var profiles: [ExerciseProfile]

    private static let range = 10...20

    private var rows: [(muscle: Muscle, sets: Int)] {
        var counts: [Muscle: Int] = [:]
        for record in records where !record.exercise.isEmpty {
            counts[Muscle.lookup(record.exercise, in: profiles), default: 0] += record.sets
        }
        return Muscle.tracked.map { (muscle: $0, sets: counts[$0] ?? 0) }
    }

    private func status(_ sets: Int) -> (label: String, color: Color) {
        if sets < Self.range.lowerBound { return (String(localized: "부족"), .orange) }
        if sets > Self.range.upperBound { return (String(localized: "많음"), .red) }
        return (String(localized: "적정"), .green)
    }

    var body: some View {
        let rows = rows
        let top = max(24, (rows.map(\.sets).max() ?? 0) + 4)
        VStack(alignment: .leading, spacing: 10) {
            Chart(rows, id: \.muscle) { row in
                RectangleMark(
                    xStart: .value("권장 시작", Self.range.lowerBound),
                    xEnd: .value("권장 끝", Self.range.upperBound),
                    y: .value("부위", row.muscle.title),
                    height: .ratio(0.9)
                )
                .foregroundStyle(Color.green.opacity(0.13))

                BarMark(x: .value("세트", row.sets), y: .value("부위", row.muscle.title), height: .ratio(0.55))
                    .cornerRadius(4)
                    .foregroundStyle(.tint)
                    .annotation(position: .trailing, spacing: 6) {
                        let status = status(row.sets)
                        HStack(spacing: 4) {
                            Text("\(row.sets)").monospacedDigit()
                            Text(status.label)
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(status.color.opacity(0.18), in: Capsule())
                                .foregroundStyle(status.color.readable)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: [0, 10, 20]) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: CGFloat(rows.count) * 32 + 24)

            Text("초록 띠는 근육별 주 10~20세트 권장 범위예요. 일반적인 근비대 기준이라 참고용이에요. 운동의 부위는 설정 → 데이터 관리 → 운동 이름 관리에서 바꿀 수 있어요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Personal records

struct ExerciseBest: Identifiable {
    let name: String
    let best: PersonalBest
    var id: String { name }

    /// Exercises with records, most recent PR first.
    static func all(in records: [WorkoutRecord]) -> [ExerciseBest] {
        Set(records.map(\.exercise)).filter { !$0.isEmpty }
            .compactMap { name in PersonalBest.of(name, in: records).map { ExerciseBest(name: name, best: $0) } }
            .sorted { ($0.best.headlineDate ?? .distantPast) > ($1.best.headlineDate ?? .distantPast) }
    }

    var isRecent: Bool {
        guard let date = best.headlineDate else { return false }
        return date > Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? date
    }
}

struct PRBoardSummary: View {
    let records: [WorkoutRecord]

    var body: some View {
        let bests = ExerciseBest.all(in: records)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(bests.prefix(5)) { item in
                NavigationLink {
                    ExerciseDetailView(name: item.name)
                } label: {
                    PRRow(item: item)
                }
                .buttonStyle(.plain)
                if item.id != bests.prefix(5).last?.id { Divider() }
            }
            if bests.count > 5 {
                NavigationLink {
                    PRBoardView()
                } label: {
                    HStack {
                        Text("전체 \(bests.count)개 운동 보기")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                    .padding(.top, 12)
                }
            }
        }
    }
}

struct PRBoardView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

    var body: some View {
        List(ExerciseBest.all(in: records)) { item in
            NavigationLink {
                ExerciseDetailView(name: item.name)
            } label: {
                PRRow(item: item)
            }
        }
        .navigationTitle("개인 기록")
    }
}

private struct PRRow: View {
    let item: ExerciseBest

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).font(.headline)
                    if item.isRecent {
                        Text("NEW")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(Color.orange.readable)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Text(headline).font(.title3.bold()).monospacedDigit()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// Bodyweight exercises are ranked by reps, everything else by weight.
    private var headline: String {
        item.best.weight > 0 ? formatWeight(item.best.weight) : String(localized: "\(item.best.reps)회")
    }

    private var detail: String {
        guard item.best.weight > 0 else { return String(localized: "맨몸 · 최다 반복") }
        let date = item.best.headlineDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        return String(localized: "추정 1RM \(formatMass(item.best.oneRepMax)) · \(date)")
    }
}

// MARK: - Exercise detail

struct ExerciseDetailView: View {
    let name: String

    enum Metric: String, CaseIterable, Identifiable {
        case weight, oneRepMax, volume, reps
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .weight: "최고 무게"
            case .oneRepMax: "추정 1RM"
            case .volume: "볼륨"
            case .reps: "최다 반복"
            }
        }
    }

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var allRecords: [WorkoutRecord]
    @Query private var profiles: [ExerciseProfile]
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue
    @State private var metric: Metric?

    private let store = ProStore.shared

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var records: [WorkoutRecord] { allRecords.filter { $0.exercise == name } }
    private var isBodyweight: Bool { records.allSatisfy { $0.bestWeight == 0 } }
    private var metrics: [Metric] { isBodyweight ? [.reps] : [.weight, .oneRepMax, .volume] }

    private func value(_ record: WorkoutRecord, _ metric: Metric) -> Double {
        switch metric {
        case .weight: unit.fromKg(record.bestWeight)
        case .oneRepMax: unit.fromKg(record.bestOneRepMax)
        case .volume: unit.fromKg(record.volume)
        case .reps: Double(record.maxReps)
        }
    }

    private func format(_ value: Double, _ metric: Metric) -> String {
        metric == .reps ? String(localized: "\(Int(value))회") : "\(value.formatted(.number.precision(.fractionLength(0...1))))\(unit.symbol)"
    }

    var body: some View {
        let best = PersonalBest.of(name, in: allRecords) ?? PersonalBest()
        let current = metric ?? metrics[0]
        let points = records.sorted { $0.date < $1.date }.suffix(30)
        List {
            Section {
                HStack(spacing: 12) {
                    if best.weight > 0 {
                        MiniStat(title: "최고 무게", value: formatWeight(best.weight, unit: unit))
                        MiniStat(title: "추정 1RM", value: formatMass(best.oneRepMax, unit: unit))
                    }
                    MiniStat(title: "최다 반복", value: String(localized: "\(best.reps)회"))
                    MiniStat(title: "총 세트", value: String(localized: "\(records.reduce(0) { $0 + $1.sets })세트"))
                }
                LabeledContent("부위", value: Muscle.lookup(name, in: profiles).title)
            }

            Section {
                if metrics.count > 1, store.isPro {
                    Picker("지표", selection: Binding(get: { current }, set: { metric = $0 })) {
                        ForEach(metrics) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if points.count >= 2 {
                    Chart(Array(points)) { record in
                        if current == .volume {
                            BarMark(x: .value("날짜", record.date, unit: .day), y: .value("값", value(record, current)))
                                .cornerRadius(3)
                                .foregroundStyle(.tint)
                        } else {
                            LineMark(x: .value("날짜", record.date, unit: .day), y: .value("값", value(record, current)))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .foregroundStyle(.tint)
                            PointMark(x: .value("날짜", record.date, unit: .day), y: .value("값", value(record, current)))
                                .symbolSize(48)
                                .foregroundStyle(.tint)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: current == .volume))
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 200)
                    .proLocked(.stats)
                    if let last = points.last {
                        Text("최근 \(format(value(last, current), current)) · 최근 \(points.count)회 기록")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("두 번 이상 기록하면 변화 그래프가 보여요").font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("기록") {
                ForEach(records) { record in
                    NavigationLink {
                        RecordEditorView(record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold())
                                Spacer()
                                Text(setsSummary(record.setValues, unit: unit)).font(.caption).foregroundStyle(.secondary)
                            }
                            // Spelled out only when the sets differ; otherwise the summary says it all.
                            if Set(record.setValues).count > 1 {
                                Text(record.setValues.map { "\(formatWeight($0.weight, unit: unit))×\($0.reps)" }.joined(separator: " · "))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(name)
    }
}

struct MiniStat: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.subheadline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
