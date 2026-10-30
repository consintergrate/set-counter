import SwiftData
import SwiftUI

struct RoutineSettingsView: View {
    @AppStorage(Routine.namesKey) private var routineRaw = Routine.defaultRaw
    @AppStorage("weeklyGoal") private var weeklyGoal = 4

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

    private var names: [String] { Routine.names(from: routineRaw) }

    private var split: Binding<Int> {
        Binding(
            get: { names.count },
            set: { routineRaw = Routine.defaultNames(for: $0).joined(separator: "|") }
        )
    }

    private func name(at index: Int) -> Binding<String> {
        Binding(
            get: { names.indices.contains(index) ? names[index] : "" },
            set: { newValue in
                var updated = names
                guard updated.indices.contains(index) else { return }
                updated[index] = newValue.replacingOccurrences(of: "|", with: "")
                routineRaw = updated.joined(separator: "|")
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("분할", selection: split) {
                    ForEach(1...6, id: \.self) { count in
                        Text(count == 1 ? String(localized: "무분할") : String(localized: "\(count)분할")).tag(count)
                    }
                }
                ForEach(names.indices, id: \.self) { index in
                    HStack {
                        Text("\(index + 1)일차")
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        TextField("부위", text: name(at: index))
                    }
                }
            } header: {
                Text("분할 루틴")
            } footer: {
                Text("운동을 마칠 때마다 다음 일차로 넘어가요. 부위 이름은 눌러서 바꿀 수 있어요.")
            }

            Section("목표") {
                WheelPickerRow(title: "주간 목표", values: Array(1...7), selection: $weeklyGoal) {
                    String(localized: "주 \($0)일")
                }
                WeeklyGoalGauge(done: Routine.weeklyDays(records: records), goal: weeklyGoal)
            }
        }
        .navigationTitle("루틴 · 목표")
    }
}

struct NotificationSettingsView: View {
    @AppStorage(Routine.namesKey) private var routineRaw = Routine.defaultRaw
    @AppStorage("notifyTime") private var notifyTime = RoutineNotifications.defaultTime
    @AppStorage("notifyWeekdays") private var notifyWeekdaysRaw = RoutineNotifications.defaultWeekdaysRaw

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(notifyTime)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                notifyTime = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60
            }
        )
    }

    private var weekdays: Set<Int> { RoutineNotifications.weekdays(from: notifyWeekdaysRaw) }

    /// Weekday numbers (1 = Sunday) in the locale's display order.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        Form {
            Section {
                DatePicker("알림 시간", selection: time, displayedComponents: .hourAndMinute)
                HStack(spacing: 6) {
                    ForEach(orderedWeekdays, id: \.self) { weekday in
                        let isOn = weekdays.contains(weekday)
                        Button {
                            toggle(weekday)
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(isOn ? nil : .secondary)
                        .fontWeight(isOn ? .bold : .regular)
                    }
                }
            } footer: {
                let names = Routine.names(from: routineRaw)
                let index = Routine.todayIndex(count: names.count, records: records)
                Text("예: \(RoutineNotifications.message(for: names[index]))\n그날 이미 운동했다면 알림이 오지 않아요.")
            }
        }
        .navigationTitle("알림 시간 · 요일")
    }

    private func toggle(_ weekday: Int) {
        var updated = weekdays
        if updated.contains(weekday) { updated.remove(weekday) } else { updated.insert(weekday) }
        notifyWeekdaysRaw = updated.sorted().map(String.init).joined(separator: ",")
    }
}

struct WeeklyGoalGauge: View {
    let done: Int
    let goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("이번 주")
                Spacer()
                Group {
                    if done >= goal {
                        Text("목표 달성! 🎉")
                    } else {
                        Text("\(done) / \(goal)일")
                    }
                }
                .monospacedDigit()
                .bold()
                .foregroundStyle(done >= goal ? Color.green.readable : Color.primary)
            }
            ProgressView(value: Double(min(done, goal)), total: Double(max(goal, 1)))
                .tint(done >= goal ? .green : nil)
        }
    }
}
