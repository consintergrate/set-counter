import SwiftData
import SwiftUI

/// Workout setup, shown as a sheet from the home screen. Starting hands the
/// session back so the home screen can present the workout full screen.
struct SetupView: View {
    var onStart: (WorkoutSession) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("exercise") private var exercise = ""
    @AppStorage("weight") private var weight = 20.0
    @AppStorage("reps") private var reps = 10
    @AppStorage("totalSets") private var totalSets = 5
    @AppStorage("restSeconds") private var restSeconds = 90
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(Routine.namesKey) private var routineRaw = Routine.defaultRaw
    @AppStorage("routineOverrideDay") private var overrideDay = 0.0
    @AppStorage("routineOverrideIndex") private var overrideIndex = 0

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

    private let restPresets = [30, 60, 90, 120, 180]

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var routineNames: [String] { Routine.names(from: routineRaw) }

    // Reads the override keys above so the view refreshes when today's part is changed.
    private var todayIndex: Int {
        _ = (overrideDay, overrideIndex)
        return Routine.todayIndex(count: routineNames.count, records: records)
    }

    private var todayName: String { routineNames[todayIndex] }

    /// Exercises done on today's part come first.
    private var recentExercises: [String] {
        var seen = Set<String>()
        let ordered = records.filter { $0.routineName == todayName } + records
        return ordered.map(\.exercise).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(6).map { $0 }
    }

    /// Wheel steps: 0.5kg or 1lb, enough for dumbbells and small plates.
    private var weightStep: Double { unit == .kg ? 0.5 : 1 }

    private var weightValues: [Double] {
        Array(stride(from: 0, through: unit == .kg ? 300 : 660, by: weightStep))
    }

    /// Lift weight in the display unit, snapped to the wheel's step; stored in kg.
    private var displayWeight: Binding<Double> {
        Binding(
            get: { min((unit.fromKg(weight) / weightStep).rounded() * weightStep, weightValues.last ?? 0) },
            set: { weight = unit.toKg($0) }
        )
    }

    /// Snapped to the wheel's 10-second steps.
    private var restBinding: Binding<Int> {
        Binding(get: { min(max((restSeconds + 5) / 10 * 10, 10), 600) }, set: { restSeconds = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("오늘 루틴") {
                        Text(todayName).bold().foregroundStyle(.tint)
                    }
                }

                Section("운동") {
                    // Pushed rather than a sheet: a sheet attached inside a Form row could
                    // be torn down when the form refreshed, closing the setup screen too.
                    NavigationLink {
                        ExercisePickerView(preferred: Coach.muscles(in: todayName)) { pick($0) }
                    } label: {
                        LabeledContent("운동") {
                            Text(exercise.isEmpty ? String(localized: "목록에서 선택") : exercise)
                                .bold()
                                .foregroundStyle(.tint)
                        }
                    }
                    if !recentExercises.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(recentExercises, id: \.self) { name in
                                    Button(name) { pick(name) }
                                        .buttonStyle(.bordered)
                                        .tint(exercise == name ? nil : .secondary)
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                    WheelPickerRow(title: "무게", values: weightValues, selection: displayWeight) {
                        formatWeight(unit.toKg($0), unit: unit)
                    }
                    WheelPickerRow(title: "반복", values: Array(1...100), selection: $reps) {
                        String(localized: "\($0)회")
                    }
                }

                Section("세트") {
                    WheelPickerRow(title: "세트 수", values: Array(1...30), selection: $totalSets) {
                        String(localized: "\($0)세트")
                    }
                }

                Section("쉬는 시간") {
                    WheelPickerRow(title: "쉬는 시간", values: Array(stride(from: 10, through: 600, by: 10)), selection: restBinding) {
                        formatDuration($0)
                    }
                    HStack(spacing: 6) {
                        ForEach(restPresets, id: \.self) { seconds in
                            Button { restSeconds = seconds } label: {
                                Text(formatDurationShort(seconds))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(restSeconds == seconds ? nil : .secondary)
                            .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("운동 준비")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    // Ask for the alarm permission when it's first needed, not at launch.
                    Task { await LockScreenAlarm.requestAuthorization() }
                    let name = exercise.trimmingCharacters(in: .whitespaces)
                    onStart(WorkoutSession(
                        exercise: name,
                        weight: weight,
                        reps: reps,
                        totalSets: totalSets,
                        restSeconds: restSeconds,
                        routineIndex: todayIndex,
                        routineName: todayName,
                        previousBest: name.isEmpty ? nil : PersonalBest.of(name, in: records)
                    ))
                } label: {
                    Text("준비 완료").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .task {
                // Reconnect a previously paired strap so it's ready before the workout starts.
                if BluetoothHeartRate.shared.hasSavedSensor { BluetoothHeartRate.shared.activate() }
            }
        }
    }

    /// Picking an exercise restores the weight and reps used last time, or a light
    /// starting weight for a listed exercise never done before.
    private func pick(_ name: String) {
        exercise = name
        if let last = records.first(where: { $0.exercise == name }) {
            weight = last.weight
            reps = last.reps
            totalSets = last.sets
        } else if let listed = ExerciseLibrary.find(name) {
            weight = listed.startWeight
            reps = 10
        }
    }
}

func formatDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let rest = seconds % 60
    switch (minutes, rest) {
    case (0, _): return String(localized: "\(rest)초")
    case (_, 0): return String(localized: "\(minutes)분")
    default: return String(localized: "\(minutes)분 \(rest)초")
    }
}

/// Compact form for the preset buttons, e.g. "1:30".
func formatDurationShort(_ seconds: Int) -> String {
    seconds % 60 == 0 || seconds < 60 ? formatDuration(seconds) : String(format: "%d:%02d", seconds / 60, seconds % 60)
}

#Preview {
    SetupView()
        .modelContainer(for: [WorkoutRecord.self, SetEntry.self, ExerciseProfile.self], inMemory: true)
}
