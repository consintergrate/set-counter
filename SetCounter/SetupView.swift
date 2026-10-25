import SwiftData
import SwiftUI

struct SetupView: View {
    @AppStorage("exercise") private var exercise = ""
    @AppStorage("weight") private var weight = 20.0
    @AppStorage("reps") private var reps = 10
    @AppStorage("totalSets") private var totalSets = 5
    @AppStorage("restSeconds") private var restSeconds = 90
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(Routine.namesKey) private var routineRaw = Routine.defaultRaw
    @AppStorage("weeklyGoal") private var weeklyGoal = 4
    @AppStorage("routineOverrideDay") private var overrideDay = 0.0
    @AppStorage("routineOverrideIndex") private var overrideIndex = 0

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @State private var session: WorkoutSession?

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

    /// Lift weight in the display unit, snapped to the unit's plate step; stored in kg.
    private var displayWeight: Binding<Double> {
        Binding(
            get: { (unit.fromKg(weight) / unit.step).rounded() * unit.step },
            set: { weight = unit.toKg($0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routineNames.count == 1 ? String(localized: "무분할 루틴") : String(localized: "\(routineNames.count)분할 · \(todayIndex + 1)일차"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("오늘은 \(todayName) 하는 날")
                                    .font(.title3.bold())
                            }
                            Spacer()
                            Menu {
                                ForEach(routineNames.indices, id: \.self) { index in
                                    Button("\(index + 1)일차 · \(routineNames[index])") {
                                        overrideDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
                                        overrideIndex = index
                                    }
                                }
                            } label: {
                                Text("바꾸기").font(.subheadline)
                            }
                        }
                        WeeklyGoalGauge(done: Routine.weeklyDays(records: records), goal: weeklyGoal)
                    }
                    .padding(.vertical, 4)
                }

                Section("운동") {
                    TextField("운동 이름 (예: 벤치프레스)", text: $exercise)
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
                    Stepper(value: displayWeight, in: 0...unit.fromKg(500), step: unit.step) {
                        LabeledContent("무게") {
                            Text(formatWeight(weight, unit: unit)).monospacedDigit().bold()
                        }
                    }
                    Stepper(value: $reps, in: 1...100) {
                        LabeledContent("반복") {
                            Text("\(reps)회").monospacedDigit().bold()
                        }
                    }
                }

                Section("세트") {
                    Stepper(value: $totalSets, in: 1...30) {
                        LabeledContent("세트 수") {
                            Text("\(totalSets)세트").monospacedDigit().bold()
                        }
                    }
                }

                Section("쉬는 시간") {
                    Stepper(value: $restSeconds, in: 10...600, step: 10) {
                        LabeledContent("쉬는 시간") {
                            Text(formatDuration(restSeconds)).monospacedDigit().bold()
                        }
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
            .navigationTitle("운동 설정")
            .safeAreaInset(edge: .bottom) {
                Button {
                    // Ask for the alarm permission when it's first needed, not at launch.
                    Task { await LockScreenAlarm.requestAuthorization() }
                    let name = exercise.trimmingCharacters(in: .whitespaces)
                    session = WorkoutSession(
                        exercise: name,
                        weight: weight,
                        reps: reps,
                        totalSets: totalSets,
                        restSeconds: restSeconds,
                        routineIndex: todayIndex,
                        routineName: todayName,
                        previousBest: name.isEmpty ? nil : PersonalBest.of(name, in: records)
                    )
                } label: {
                    Text("운동 준비").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .fullScreenCover(item: $session) { session in
                WorkoutView(session: session)
            }
            .task {
                // Reconnect a previously paired strap so it's ready before the workout starts.
                if BluetoothHeartRate.shared.hasSavedSensor { BluetoothHeartRate.shared.activate() }
            }
        }
    }

    /// Picking a recent exercise also restores the weight and reps used last time.
    private func pick(_ name: String) {
        exercise = name
        guard let last = records.first(where: { $0.exercise == name }) else { return }
        weight = last.weight
        reps = last.reps
        totalSets = last.sets
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
