import Charts
import SwiftData
import SwiftUI

/// What filled the activity rings on a day: each workout behind the exercise ring,
/// the past week's minutes against the goal, and active energy and steps.
struct ActivityDetailView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

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
        let sessions = health.exerciseSessions(on: day, records: records)
        let minutes = health.exerciseMinutes(on: day, records: records)
        let active = health.dailyActive[day] ?? 0
        let steps = health.dailySteps[day] ?? 0

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

                ringsSummary(goals: goals, minutes: minutes, active: active, steps: steps)
                exerciseCard(sessions: sessions, minutes: minutes, goal: goals.exerciseMinutes)
                weekChart(goal: goals.exerciseMinutes)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("활동")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await health.refresh() }
    }

    private func ringsSummary(goals: Goals, minutes: Double, active: Double, steps: Double) -> some View {
        let rows: [(title: LocalizedStringKey, value: String, goal: String, progress: Double, color: Color)] = [
            ("활동", "\(Int(active).formatted())kcal", "\(goals.activeCalories.formatted())kcal",
             active / Double(max(goals.activeCalories, 1)), .pink),
            ("운동", String(localized: "\(Int(minutes))분"), String(localized: "\(goals.exerciseMinutes)분"),
             minutes / Double(max(goals.exerciseMinutes, 1)), .green),
            ("걸음", Int(steps).formatted(), String(localized: "\(goals.steps.formatted())보"),
             steps / Double(max(goals.steps, 1)), .cyan),
        ]
        return VStack(spacing: 18) {
            ActivityRingsGraphic(rings: rows.map { ($0.progress, $0.color) }, diameter: 170, lineWidth: 18)
                .frame(width: 180, height: 180)
                .animation(.easeOut(duration: 0.5), value: dayOffset)
            HStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    VStack(spacing: 2) {
                        Text(row.title).font(.caption.weight(.semibold)).foregroundStyle(row.color.readable)
                        Text(row.value).font(.headline).monospacedDigit()
                        Text("/ \(row.goal)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        Text("\(min(Int((row.progress * 100).rounded()), 999))%")
                            .font(.caption.bold())
                            .monospacedDigit()
                            .foregroundStyle(row.progress >= 1 ? AnyShapeStyle(Color.green.readable) : AnyShapeStyle(.secondary))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func exerciseCard(sessions: [ExerciseSession], minutes: Double, goal: Int) -> some View {
        let rawMinutes = sessions.reduce(0) { $0 + $1.interval.duration } / 60
        let overlap = Int((rawMinutes - minutes).rounded())
        return ReportCard(title: "운동 시간", systemImage: "figure.mixed.cardio", color: .green) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(localized: "\(Int(minutes))분")).font(.title.bold()).monospacedDigit()
                Text("/ \(String(localized: "\(goal)분"))").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if minutes >= Double(goal) {
                    Label("목표 달성", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.green.readable)
                } else {
                    Text(String(localized: "\(goal - Int(minutes))분 남음"))
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }
            if sessions.isEmpty {
                Text("이 날은 운동 기록이 없어요. 세트 카운터로 운동하거나 다른 앱에서 러닝·걷기를 하면 여기에 쌓여요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                HStack(spacing: 12) {
                    Image(systemName: session.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(session.isCardio ? .teal : .orange)
                        .frame(width: 32, height: 32)
                        .background((session.isCardio ? Color.teal : Color.orange).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title).font(.subheadline.bold()).lineLimit(1)
                        Text("\(session.interval.start.formatted(date: .omitted, time: .shortened)) – \(session.interval.end.formatted(date: .omitted, time: .shortened)) · \(session.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(String(localized: "\(max(Int((session.interval.duration / 60).rounded()), 1))분"))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            Text(overlap > 0
                 ? String(localized: "겹친 시간 \(overlap)분은 한 번만 셌어요. 세트 카운터 근력 운동과 다른 앱(나이키 런 클럽, 피트니스 등)의 운동을 합친 시간이에요.")
                 : String(localized: "세트 카운터 근력 운동과 다른 앱(나이키 런 클럽, 피트니스 등)의 운동을 합친 시간이에요."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The seven days ending on the selected day.
    private func weekChart(goal: Int) -> some View {
        let days = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
        let values = days.map { (day: $0, minutes: health.exerciseMinutes(on: $0, records: records)) }
        let average = values.reduce(0) { $0 + $1.minutes } / Double(values.count)
        let reached = values.filter { $0.minutes >= Double(goal) }.count
        return ReportCard(title: "최근 7일", systemImage: "chart.bar.fill", color: .green) {
            HStack {
                MiniStat(title: "하루 평균", value: String(localized: "\(Int(average.rounded()))분"))
                MiniStat(title: "목표 달성", value: String(localized: "\(reached)/7일"))
            }
            Chart {
                ForEach(values, id: \.day) { item in
                    BarMark(x: .value("날짜", item.day, unit: .day), y: .value("분", item.minutes))
                        .cornerRadius(4)
                        .foregroundStyle(item.minutes >= Double(goal) ? Color.green : Color.green.opacity(0.45))
                        .opacity(calendar.isDate(item.day, inSameDayAs: day) ? 1 : 0.8)
                }
                RuleMark(y: .value("목표", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text(String(localized: "목표 \(goal)분")).font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: days) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                        }
                    }
                }
            }
            .frame(height: 150)
        }
    }
}
