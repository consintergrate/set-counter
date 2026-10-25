import Charts
import SwiftUI

/// Minutes of cardio from Health per week or month, against the weekly goal.
struct CardioChart: View {
    let period: StatsView.Period
    let health: HealthData
    let weeklyGoal: Int

    private struct Bucket: Identifiable {
        let start: Date
        let minutes: Double
        let distance: Double
        var id: Date { start }
    }

    private var buckets: [Bucket] {
        let calendar = Calendar.current
        guard let current = calendar.dateInterval(of: period.component, for: Date())?.start else { return [] }
        return (0..<period.bucketCount).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: period.component, value: -offset, to: current),
                  let end = calendar.date(byAdding: period.component, value: 1, to: start) else { return nil }
            let workouts = health.cardio.filter { $0.isCardio && $0.start >= start && $0.start < end }
            return Bucket(start: start,
                          minutes: workouts.reduce(0) { $0 + $1.duration } / 60,
                          distance: workouts.reduce(0) { $0 + $1.distance })
        }
    }

    var body: some View {
        let buckets = buckets
        VStack(alignment: .leading, spacing: 8) {
            if let current = buckets.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "\(Int(current.minutes))분"))
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text(formatDistance(current.distance))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(period == .week ? String(localized: "이번 주") : String(localized: "이번 달"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(buckets) { bucket in
                    BarMark(
                        x: .value("기간", bucket.start, unit: period.component),
                        y: .value("분", bucket.minutes),
                        width: .ratio(0.6)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(bucket.minutes >= Double(weeklyGoal) && period == .week ? Color.green : Color.teal)
                }
                if period == .week, weeklyGoal > 0 {
                    RuleMark(y: .value("목표", weeklyGoal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("목표 \(weeklyGoal)분").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: buckets.map(\.start)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(period == .week
                                 ? date.formatted(.dateTime.month(.defaultDigits).day())
                                 : date.formatted(.dateTime.month(.abbreviated)))
                        }
                    }
                }
            }
            .frame(height: 160)
            Text("나이키 런 클럽, 피트니스, 스트라바 등에서 건강 앱에 저장한 운동이에요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The last three months of body weight, linking to the full weight screen.
struct WeightTrendCard: View {
    let health: HealthData
    let goalWeight: Double

    var body: some View {
        let since = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let entries = health.weights.filter { $0.date >= since }
        let unit = WeightUnit.current
        NavigationLink {
            WeightView()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(health.latestWeight.map { formatMass($0.kg) } ?? "–")
                        .font(.title2.bold())
                        .monospacedDigit()
                    if let first = entries.first, let last = entries.last, first.date != last.date {
                        let change = last.kg - first.kg
                        Text("3개월 \(change > 0 ? "+" : "")\(formatMass(change))")
                            .font(.subheadline)
                            .foregroundStyle(change <= 0 ? .green : .orange)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                if entries.count >= 2 {
                    let showGoal = Goals.hasGoalWeight
                    let values = entries.map { unit.fromKg($0.kg) } + (showGoal ? [unit.fromKg(goalWeight)] : [])
                    Chart {
                        ForEach(entries) { entry in
                            LineMark(x: .value("날짜", entry.date), y: .value("체중", unit.fromKg(entry.kg)))
                                .interpolationMethod(.monotone)
                        }
                        if showGoal {
                            RuleMark(y: .value("목표", unit.fromKg(goalWeight)))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.green)
                        }
                    }
                    .chartYScale(domain: ((values.min() ?? 0) - 1)...((values.max() ?? 0) + 1))
                    .frame(height: 120)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
