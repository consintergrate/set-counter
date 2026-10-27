import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var component: Calendar.Component { self == .week ? .weekOfYear : .month }
        var bucketCount: Int { self == .week ? 8 : 6 }
    }

    struct Bucket: Identifiable {
        let start: Date
        let records: [WorkoutRecord]
        var id: Date { start }

        var days: Int { Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count }
        var volume: Double { records.reduce(0) { $0 + $1.volume } }
        var calories: Double { records.reduce(0) { $0 + $1.calories } }
        var duration: TimeInterval { records.reduce(0) { $0 + $1.duration } }
        var sets: Int { records.reduce(0) { $0 + $1.sets } }
    }

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @AppStorage("weeklyGoal") private var weeklyGoal = 4
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(Goals.cardioKey) private var cardioGoal = 150
    @AppStorage(Goals.goalWeightKey) private var goalWeight = 68.0
    @State private var period = Period.week

    private let health = HealthData.shared
    private let store = ProStore.shared

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var buckets: [Bucket] {
        let calendar = Calendar.current
        guard let current = calendar.dateInterval(of: period.component, for: Date())?.start else { return [] }
        return (0..<period.bucketCount).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: period.component, value: -offset, to: current),
                  let end = calendar.date(byAdding: period.component, value: 1, to: start) else { return nil }
            return Bucket(start: start, records: records.filter { $0.date >= start && $0.date < end })
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("기간", selection: $period) {
                    Text("주간").tag(Period.week)
                    Text("월간").tag(Period.month)
                }
                .pickerStyle(.segmented)

                if records.isEmpty {
                    ContentUnavailableView(
                        "아직 통계가 없어요",
                        systemImage: "chart.bar",
                        description: Text("운동을 기록하면 여기에 통계가 쌓여요.")
                    )
                    .padding(.top, 40)
                } else {
                    let buckets = buckets
                    SummaryGrid(period: period, current: buckets.last, previous: buckets.dropLast().last, unit: unit,
                                showsChange: store.isPro)

                    ChartCard(title: "운동한 날") {
                        BucketBarChart(period: period, buckets: buckets, goal: period == .week ? weeklyGoal : nil) {
                            Double($0.days)
                        } format: {
                            String(localized: "\(Int($0))일")
                        }
                    }

                    ChartCard(title: "볼륨") {
                        BucketBarChart(period: period, buckets: buckets, goal: nil) {
                            unit.fromKg($0.volume)
                        } format: {
                            "\(Int($0).formatted())\(unit.symbol)"
                        }
                        .proLocked(.stats)
                    }

                    ChartCard(title: "운동 잔디") {
                        ActivityHeatmap(records: records, weeklyGoal: weeklyGoal)
                            .proLocked(.stats)
                    }

                    ChartCard(title: "최근 7일 부위 균형") {
                        // A rolling week, so the check isn't empty every Monday morning.
                        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                        BalanceChart(records: records.filter { $0.date > since })
                            .proLocked(.stats)
                    }

                    ChartCard(title: "개인 기록") {
                        PRBoardSummary(records: records)
                            .proLocked(.stats)
                    }
                }

                if !health.cardio.isEmpty {
                    ChartCard(title: "유산소") {
                        CardioChart(period: period, health: health, weeklyGoal: cardioGoal)
                            .proLocked(.stats)
                    }
                }
                if !health.weights.isEmpty {
                    ChartCard(title: "체중") {
                        WeightTrendCard(health: health, goalWeight: goalWeight)
                            .proLocked(.diet)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("통계")
    }
}

struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SummaryGrid: View {
    let period: StatsView.Period
    let current: StatsView.Bucket?
    let previous: StatsView.Bucket?
    let unit: WeightUnit
    /// Change against the previous period is a Pro comparison.
    let showsChange: Bool

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        VStack(alignment: .leading, spacing: 8) {
            Text(period == .week ? String(localized: "이번 주") : String(localized: "이번 달"))
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                StatTile(title: "운동한 날", value: String(localized: "\(current?.days ?? 0)일"),
                         delta: delta(current?.days, previous?.days))
                StatTile(title: "총 볼륨", value: formatMass(current?.volume ?? 0, unit: unit),
                         delta: delta(current?.volume, previous?.volume))
                StatTile(title: "칼로리", value: "\(Int(current?.calories ?? 0).formatted()) kcal",
                         delta: delta(current?.calories, previous?.calories))
                StatTile(title: "운동 시간", value: formatClock(current?.duration ?? 0),
                         delta: delta(current?.duration, previous?.duration))
            }
        }
    }

    /// Change vs the previous period, as a percentage; nil when there's nothing to compare.
    /// An empty period that has only just started isn't "-100%", so it shows nothing.
    private func delta<T: BinaryInteger>(_ now: T?, _ before: T?) -> Int? {
        delta(now.map(Double.init), before.map(Double.init))
    }

    private func delta(_ now: Double?, _ before: Double?) -> Int? {
        guard showsChange, let now, now > 0, let before, before > 0 else { return nil }
        return Int(((now - before) / before * 100).rounded())
    }
}

private struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    let delta: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let delta {
                Label("\(delta > 0 ? "+" : "")\(delta)%", systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(" ").font(.caption2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One bar per week or month. Tapping or dragging over a bar shows its value.
private struct BucketBarChart: View {
    let period: StatsView.Period
    let buckets: [StatsView.Bucket]
    let goal: Int?
    let value: (StatsView.Bucket) -> Double
    let format: (Double) -> String

    @State private var selectedDate: Date?

    private var selected: StatsView.Bucket? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        return buckets.first { calendar.isDate($0.start, equalTo: selectedDate, toGranularity: period.component) }
    }

    private func label(_ date: Date) -> String {
        period == .week
            ? String(localized: "\(date.formatted(.dateTime.month(.defaultDigits).day())) 주")
            : date.formatted(.dateTime.year().month(.abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Readout doubles as the tooltip: latest period by default, the touched bar while scrubbing.
            let shown = selected ?? buckets.last
            HStack(alignment: .firstTextBaseline) {
                Text(shown.map { format(value($0)) } ?? "-")
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(shown.map { label($0.start) } ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(buckets) { bucket in
                    BarMark(
                        x: .value("기간", bucket.start, unit: period.component),
                        y: .value("값", value(bucket)),
                        width: .ratio(0.6)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(.tint)
                    .opacity(selected == nil || selected?.id == bucket.id ? 1 : 0.35)
                }
                if let goal {
                    RuleMark(y: .value("목표", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("목표 \(goal)일").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: buckets.map(\.start)) { mark in
                    AxisValueLabel {
                        if let date = mark.as(Date.self) {
                            Text(period == .week
                                 ? date.formatted(.dateTime.month(.defaultDigits).day())
                                 : date.formatted(.dateTime.month(.abbreviated)))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
        }
    }
}
