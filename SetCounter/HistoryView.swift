import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var month: Date
    @State private var selectedDay: Date

    /// Opens on `day` (today by default), e.g. from a row in Home's recent workouts.
    init(day: Date = Date()) {
        _month = State(initialValue: Calendar.current.startOfMonth(for: day))
        _selectedDay = State(initialValue: Calendar.current.startOfDay(for: day))
    }

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

    /// In the order they were done.
    private var dayRecords: [WorkoutRecord] {
        records.filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }.reversed()
    }

    var body: some View {
        List {
            Section {
                MonthCalendar(month: $month, selectedDay: $selectedDay, workoutDays: workoutDays, cardioDays: cardioDays)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } footer: {
                // One line: the legend doubles as the month's totals.
                let strengthDays = workoutDays.filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }.count
                let cardioCount = health.cardio.filter { $0.isCardio && calendar.isDate($0.start, equalTo: month, toGranularity: .month) }.count
                HStack(spacing: 12) {
                    Label(String(localized: "근력 \(strengthDays)일"), systemImage: "circle.fill").foregroundStyle(Color.orange.readable)
                    Label(String(localized: "유산소 \(cardioCount)회"), systemImage: "circle.fill").foregroundStyle(Color.teal.readable)
                    Spacer()
                    Text("\(Int(monthRecords.reduce(0) { $0 + $1.calories }).formatted())kcal")
                        .monospacedDigit()
                }
                .labelStyle(LegendLabelStyle())
            }

            Section {
                if dayRecords.isEmpty, dayCardio.isEmpty {
                    Text("이 날은 운동 기록이 없어요")
                        .foregroundStyle(.secondary)
                }
                ForEach(dayCardio) { workout in
                    CardioRow(workout: workout)
                }
                if !dayRecords.isEmpty {
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
            } header: {
                dayHeader
            }
        }
        .navigationTitle("운동 기록")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink {
                RecordEditorView(newOn: selectedDay)
            } label: {
                Label("기록 추가", systemImage: "plus")
            }
        }
    }

    /// Date on the left, the day's routine and totals on the right.
    private var dayHeader: some View {
        let sets = dayRecords.reduce(0) { $0 + $1.sets }
        let volume = dayRecords.reduce(0) { $0 + $1.volume }
        let part = dayRecords.first(where: { !$0.routineName.isEmpty })?.routineName
        return HStack(alignment: .firstTextBaseline) {
            Text(selectedDay.formatted(.dateTime.month().day().weekday(.wide)))
            Spacer()
            if !dayRecords.isEmpty {
                Text([part, String(localized: "\(sets)세트"), volume > 0 ? formatMass(volume) : nil].compactMap { $0 }.joined(separator: " · "))
                    .monospacedDigit()
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
                    .accessibilityLabel("이전 달")
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("다음 달")
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
        HistoryRowLayout(
            systemImage: "dumbbell.fill",
            color: .orange,
            title: record.exercise.isEmpty ? String(localized: "운동") : record.exercise,
            subtitle: setsSummary(record.setValues),
            time: record.date,
            detail: record.calories > 0 ? "\(Int(record.calories).formatted())kcal" : formatClock(record.duration)
        )
    }
}

/// The shared row: icon, title and one line of detail, time and one number on the right.
private struct HistoryRowLayout: View {
    let systemImage: String
    let color: Color
    let title: String
    var badge: String?
    let subtitle: String
    let time: Date
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.bold()).lineLimit(1)
                    if let badge {
                        Text(badge).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption.bold())
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A run, walk, or ride from another app, read from Health.
struct CardioRow: View {
    let workout: CardioWorkout

    var body: some View {
        HistoryRowLayout(
            // Teal for cardio, orange like this app's own records for strength.
            systemImage: workout.systemImage,
            color: workout.isCardio ? .teal : .orange,
            title: workout.title,
            badge: workout.source,
            subtitle: workout.summary,
            time: workout.start,
            detail: workout.energy > 0 ? "\(Int(workout.energy).formatted())kcal" : formatClock(workout.duration)
        )
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
