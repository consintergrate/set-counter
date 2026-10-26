import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var month = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    private let health = HealthData.shared
    private var calendar: Calendar { .current }

    /// Strength days: this app's records plus strength workouts from other apps
    /// (an Apple Watch "근력 운동", for example).
    private var workoutDays: Set<Date> {
        Set(records.map { calendar.startOfDay(for: $0.date) })
            .union(health.cardio.filter { !$0.isCardio }.map { calendar.startOfDay(for: $0.start) })
    }

    /// Runs, walks, rides and other cardio that other apps saved to Health.
    private var cardioDays: Set<Date> {
        Set(health.cardio.filter(\.isCardio).map { calendar.startOfDay(for: $0.start) })
    }

    private var dayCardio: [CardioWorkout] {
        health.cardio.filter { calendar.isDate($0.start, inSameDayAs: selectedDay) }
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
                MonthCalendar(month: $month, selectedDay: $selectedDay, workoutDays: workoutDays, cardioDays: cardioDays)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } footer: {
                let days = Set(monthRecords.map { calendar.startOfDay(for: $0.date) }).count
                let calories = monthRecords.reduce(0) { $0 + $1.calories }
                let cardio = health.cardio.filter { calendar.isDate($0.start, equalTo: month, toGranularity: .month) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("이번 달 \(days)일 운동 · \(monthRecords.count)개 기록 · \(Int(calories)) kcal")
                    if !cardio.isEmpty {
                        Text("다른 앱 운동 \(cardio.count)회 · \(formatDistance(cardio.reduce(0) { $0 + $1.distance }))")
                    }
                    HStack(spacing: 12) {
                        Label("근력", systemImage: "circle.fill").foregroundStyle(.orange)
                        Label("유산소", systemImage: "circle.fill").foregroundStyle(.teal)
                    }
                    .labelStyle(LegendLabelStyle())
                }
            }

            Section(selectedDay.formatted(.dateTime.month().day().weekday(.wide))) {
                ForEach(dayCardio) { workout in
                    CardioRow(workout: workout)
                }
                if dayRecords.isEmpty {
                    if dayCardio.isEmpty {
                        Text("이 날은 운동 기록이 없어요")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(dayRecords) { record in
                        NavigationLink {
                            RecordEditorView(record: record)
                        } label: {
                            RecordRow(record: record)
                        }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { dayRecords[$0] }
                        targets.forEach(modelContext.delete)
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle("운동 기록")
        .toolbar {
            NavigationLink {
                RecordEditorView(newOn: selectedDay)
            } label: {
                Label("기록 추가", systemImage: "plus")
            }
        }
    }
}

private struct MonthCalendar: View {
    @Binding var month: Date
    @Binding var selectedDay: Date
    let workoutDays: Set<Date>
    let cardioDays: Set<Date>

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
                            hasWorkout: workoutDays.contains(day),
                            hasCardio: cardioDays.contains(day)
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
    let hasCardio: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary))
                .frame(width: 30, height: 30)
                .background(Circle().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear)))
            HStack(spacing: 3) {
                if hasWorkout { Circle().fill(Color.orange).frame(width: 5, height: 5) }
                if hasCardio { Circle().fill(Color.teal).frame(width: 5, height: 5) }
            }
            .frame(height: 5)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
    }
}

struct RecordRow: View {
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
            Text(setsSummary(record.setValues))
                .monospacedDigit()
            HStack(spacing: 12) {
                Label(formatClock(record.duration), systemImage: "clock")
                if record.volume > 0 {
                    Label(formatMass(record.volume), systemImage: "scalemass")
                }
                if record.calories > 0 {
                    Label("\(Int(record.calories).formatted())kcal", systemImage: "flame")
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

/// A run, walk, or ride from another app, read from Health.
struct CardioRow: View {
    let workout: CardioWorkout

    /// Teal for cardio, orange like this app's own records for strength.
    private var color: Color { workout.isCardio ? .teal : .orange }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.systemImage)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(workout.title).font(.headline)
                    Text(workout.source)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15), in: Capsule())
                        .foregroundStyle(color)
                    Spacer()
                    Text(workout.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(workout.summary).monospacedDigit()
                HStack(spacing: 12) {
                    if workout.energy > 0 {
                        Label("\(Int(workout.energy).formatted())kcal", systemImage: "flame")
                    }
                    if workout.averageHeartRate > 0 {
                        Label("\(workout.averageHeartRate)", systemImage: "heart")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Small colored dot followed by the title, for chart and calendar legends.
struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title.foregroundStyle(Color.secondary)
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
