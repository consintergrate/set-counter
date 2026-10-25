import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var month = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { .current }

    private var workoutDays: Set<Date> {
        Set(records.map { calendar.startOfDay(for: $0.date) })
    }

    private var monthRecords: [WorkoutRecord] {
        records.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var dayRecords: [WorkoutRecord] {
        records.filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
    }

    var body: some View {
        List {
            Section {
                MonthCalendar(month: $month, selectedDay: $selectedDay, workoutDays: workoutDays)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } footer: {
                let days = Set(monthRecords.map { calendar.startOfDay(for: $0.date) }).count
                let calories = monthRecords.reduce(0) { $0 + $1.calories }
                Text("이번 달 \(days)일 운동 · \(monthRecords.count)개 기록 · \(Int(calories)) kcal")
            }

            Section(selectedDay.formatted(.dateTime.month().day().weekday(.wide))) {
                if dayRecords.isEmpty {
                    Text("이 날은 운동 기록이 없어요")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dayRecords) { record in
                        RecordRow(record: record)
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { dayRecords[$0] }
                        targets.forEach(modelContext.delete)
                    }
                }
            }
        }
        .navigationTitle("운동 기록")
    }
}

private struct MonthCalendar: View {
    @Binding var month: Date
    @Binding var selectedDay: Date
    let workoutDays: Set<Date>

    private var calendar: Calendar { .current }

    /// Leading blanks for the first week, then each day of the month.
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let blanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: blanks) + days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            day: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                            isToday: calendar.isDateInToday(day),
                            hasWorkout: workoutDays.contains(day)
                        )
                        .onTapGesture { selectedDay = day }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private func shiftMonth(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        month = next
        selectedDay = calendar.isDate(Date(), equalTo: next, toGranularity: .month) ? calendar.startOfDay(for: Date()) : next
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let hasWorkout: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary))
                .frame(width: 30, height: 30)
                .background(Circle().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear)))
            Circle()
                .fill(hasWorkout ? Color.orange : .clear)
                .frame(width: 5, height: 5)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
    }
}

private struct RecordRow: View {
    let record: WorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.exercise.isEmpty ? String(localized: "운동") : record.exercise).font(.headline)
                if !record.routineName.isEmpty {
                    Text(record.routineName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text(record.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(formatWeight(record.weight)) × \(record.reps)회 × \(record.sets)세트")
                .monospacedDigit()
            HStack(spacing: 12) {
                Label(formatClock(record.duration), systemImage: "clock")
                if record.volume > 0 {
                    Label(formatMass(record.volume), systemImage: "scalemass")
                }
                if record.calories > 0 {
                    Label("\(Int(record.calories))kcal", systemImage: "flame")
                }
                if record.averageHeartRate > 0 {
                    Label("\(record.averageHeartRate)", systemImage: "heart")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
