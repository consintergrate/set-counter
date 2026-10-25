import SwiftData
import SwiftUI

/// Edits a saved workout record, or adds one by hand for a past workout.
struct RecordEditorView: View {
    private let record: WorkoutRecord?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(Routine.namesKey) private var routineRaw = Routine.defaultRaw

    @State private var exercise: String
    @State private var date: Date
    @State private var routineName: String
    @State private var sets: [SetValue]
    @State private var minutes: Int
    @State private var calories: Int
    @State private var confirmingDelete = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    init(record: WorkoutRecord) {
        self.record = record
        _exercise = State(initialValue: record.exercise)
        _date = State(initialValue: record.date)
        _routineName = State(initialValue: record.routineName)
        _sets = State(initialValue: record.setValues)
        _minutes = State(initialValue: Int((record.duration / 60).rounded()))
        _calories = State(initialValue: Int(record.calories))
    }

    /// A new record on `day`, at the current time of day.
    init(newOn day: Date) {
        self.record = nil
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: Date())
        _exercise = State(initialValue: UserDefaults.standard.string(forKey: "exercise") ?? "")
        _date = State(initialValue: calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day)
        _routineName = State(initialValue: "")
        _sets = State(initialValue: Array(repeating: SetValue(weight: 20, reps: 10), count: 3))
        _minutes = State(initialValue: 15)
        _calories = State(initialValue: 0)
    }

    private var knownExercises: [String] {
        var seen = Set<String>()
        return records.map(\.exercise).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var trimmedName: String { exercise.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section("운동") {
                HStack {
                    TextField("운동 이름", text: $exercise)
                    if !knownExercises.isEmpty {
                        Menu {
                            ForEach(knownExercises, id: \.self) { name in
                                Button(name) { exercise = name }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("운동 목록에서 고르기")
                    }
                }
                Picker("루틴 부위", selection: $routineName) {
                    Text("없음").tag("")
                    ForEach(routineChoices, id: \.self) { Text($0).tag($0) }
                }
                DatePicker("날짜", selection: $date)
            }

            Section {
                ForEach(sets.indices, id: \.self) { index in
                    SetRow(index: index, value: $sets[index], unit: unit)
                }
                .onDelete { sets.remove(atOffsets: $0) }
                Button("세트 추가", systemImage: "plus.circle") {
                    sets.append(sets.last ?? SetValue(weight: 20, reps: 10))
                }
            } header: {
                Text("세트")
            } footer: {
                Text(sets.isEmpty ? "세트를 하나 이상 추가해주세요." : "총 볼륨 \(formatMass(sets.reduce(0) { $0 + $1.volume }, unit: unit)) · 밀어서 세트 삭제")
            }

            Section("기타") {
                Stepper(value: $minutes, in: 0...300, step: 5) {
                    LabeledContent("운동 시간", value: String(localized: "\(minutes)분"))
                }
                LabeledContent("칼로리") {
                    HStack(spacing: 4) {
                        TextField("0", value: $calories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                }
            }

            if record != nil {
                Section {
                    Button("기록 삭제", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(record == nil ? "기록 추가" : "기록 수정")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장", action: save)
                    .disabled(trimmedName.isEmpty || sets.isEmpty)
            }
        }
        .confirmationDialog("이 기록을 삭제할까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let record { modelContext.delete(record) }
                try? modelContext.save()
                dismiss()
            }
        }
    }

    /// Routine parts, plus this record's own part if it isn't in the routine any more.
    private var routineChoices: [String] {
        let names = Routine.names(from: routineRaw)
        return routineName.isEmpty || names.contains(routineName) ? names : names + [routineName]
    }

    private func save() {
        let target: WorkoutRecord
        if let record {
            target = record
        } else {
            target = WorkoutRecord(date: date, exercise: trimmedName, sets: 0, weight: 0, reps: 0, duration: 0)
            modelContext.insert(target)
        }
        target.exercise = trimmedName
        target.date = date
        target.routineName = routineName
        target.routineIndex = Routine.names(from: routineRaw).firstIndex(of: routineName) ?? -1
        target.duration = TimeInterval(minutes * 60)
        target.calories = Double(calories)
        target.replaceSets(sets, in: modelContext)
        try? modelContext.save()
        dismiss()
    }
}

private struct SetRow: View {
    let index: Int
    @Binding var value: SetValue
    let unit: WeightUnit

    /// Weight typed in the display unit, stored in kg.
    private var weight: Binding<Double> {
        Binding(
            get: { (unit.fromKg(value.weight) * 10).rounded() / 10 },
            set: { value.weight = max(0, unit.toKg($0)) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)세트")
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            HStack(spacing: 4) {
                TextField("0", value: weight, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(unit.symbol).foregroundStyle(.secondary)
            }
            Stepper(value: $value.reps, in: 1...200) {
                Text("\(value.reps)회").monospacedDigit()
            }
            .fixedSize()
        }
    }
}
