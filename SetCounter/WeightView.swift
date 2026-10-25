import Charts
import SwiftUI

/// Body weight trend from Health (any app or scale that writes there) against the goal.
struct WeightView: View {
    @AppStorage(Goals.goalWeightKey) private var goalWeight = 68.0
    @AppStorage(Goals.weeklyLossKey) private var weeklyLoss = 0.5
    @AppStorage(Goals.heightKey) private var heightCm = 172.0
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue

    @State private var range = Range.threeMonths
    @State private var showingAdd = false

    private let health = HealthData.shared
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    enum Range: CaseIterable, Identifiable {
        case month, threeMonths, year
        var id: Self { self }
        var days: Int { switch self { case .month: 30; case .threeMonths: 90; case .year: 365 } }
        var title: LocalizedStringKey { switch self { case .month: "1개월"; case .threeMonths: "3개월"; case .year: "1년" } }
    }

    private var entries: [WeightEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -range.days, to: Date()) ?? Date()
        return health.weights.filter { $0.date >= start }
    }

    var body: some View {
        let entries = entries
        List {
            if health.needsAuthorization {
                Section {
                    Button("건강 앱 연결하기", systemImage: "heart.text.square") {
                        Task { await health.requestAuthorization() }
                    }
                }
            }

            Section {
                summary(entries)
                Picker("기간", selection: $range) {
                    ForEach(Range.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                chart(entries)
            }

            Section {
                GoalWeightRow()
                WeeklyLossPicker()
                NavigationLink("걸음 · 활동 · 유산소 목표") { GoalsSettingsView() }
            } header: {
                Text("목표")
            } footer: {
                let _ = (goalWeight, weeklyLoss)
                Text("목표 체중을 눌러 바꿀 수 있어요. 감량 속도에 맞춰 하루 기본 목표가 \(Int(Goals.saved.intakeTarget(profile: .saved)).formatted())kcal로 잡혀 있고, 활동 칼로리는 그날 따로 더해져요.")
            }

            Section {
                if health.weights.isEmpty {
                    Text("아직 체중 기록이 없어요. 오른쪽 위 + 로 기록하거나, 체중계 앱이 건강 앱에 저장하면 자동으로 보여요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(health.weights.reversed().prefix(30)) { entry in
                    LabeledContent {
                        Text(formatMass(entry.kg, unit: unit)).monospacedDigit().bold().foregroundStyle(.primary)
                    } label: {
                        Text(entry.date.formatted(.dateTime.month().day().weekday().hour().minute()))
                    }
                }
            } header: {
                Text("기록")
            } footer: {
                Text("기록 삭제는 건강 앱 → 체중에서 할 수 있어요.")
            }
        }
        .navigationTitle("체중")
        .toolbar {
            Button("체중 기록", systemImage: "plus") { showingAdd = true }
        }
        .sheet(isPresented: $showingAdd) {
            WeightEntrySheet(initialKg: health.latestWeight?.kg ?? UserDefaults.standard.object(forKey: "bodyWeight") as? Double ?? 70, unit: unit)
        }
        .refreshable { await health.refresh() }
    }

    private func summary(_ entries: [WeightEntry]) -> some View {
        let latest = health.latestWeight
        let change = entries.count >= 2 ? (entries.last?.kg ?? 0) - (entries.first?.kg ?? 0) : nil
        let bmi = latest.map { $0.kg / pow(heightCm / 100, 2) }
        return HStack(spacing: 0) {
            MiniStat(title: "현재", value: latest.map { formatMass($0.kg, unit: unit) } ?? "–")
            MiniStat(title: "기간 변화", value: change.map { ($0 > 0 ? "+" : "") + formatMass($0, unit: unit) } ?? "–")
            MiniStat(title: "목표까지", value: Goals.hasGoalWeight ? latest.map { formatMass(max($0.kg - goalWeight, 0), unit: unit) } ?? "–" : "–")
            MiniStat(title: "BMI", value: bmi.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
        }
    }

    @ViewBuilder
    private func chart(_ entries: [WeightEntry]) -> some View {
        if entries.isEmpty {
            Text("이 기간에는 기록이 없어요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            let showGoal = Goals.hasGoalWeight
            let values = entries.map { unit.fromKg($0.kg) } + (showGoal ? [unit.fromKg(goalWeight)] : [])
            let low = (values.min() ?? 0) - 1, high = (values.max() ?? 0) + 1
            Chart {
                ForEach(entries) { entry in
                    LineMark(x: .value("날짜", entry.date), y: .value("체중", unit.fromKg(entry.kg)))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("날짜", entry.date), y: .value("체중", unit.fromKg(entry.kg)))
                        .symbolSize(entries.count > 40 ? 8 : 24)
                }
                if showGoal {
                    RuleMark(y: .value("목표", unit.fromKg(goalWeight)))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(.green)
                        .annotation(position: .top, alignment: .leading) {
                            Text("목표 \(formatMass(goalWeight, unit: unit))").font(.caption2.bold()).foregroundStyle(.green)
                        }
                }
            }
            .chartYScale(domain: low...high)
            .frame(height: 200)
            .padding(.vertical, 6)
        }
    }
}

/// Two wheels (whole and tenths) so any weight is a couple of flicks away.
struct WeightEntrySheet: View {
    let unit: WeightUnit
    @State private var whole: Int
    @State private var tenth: Int
    @State private var date = Date()
    @State private var saving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    init(initialKg: Double, unit: WeightUnit) {
        self.unit = unit
        let value = (unit.fromKg(initialKg) * 10).rounded() / 10
        _whole = State(initialValue: Int(value))
        _tenth = State(initialValue: Int(((value - Double(Int(value))) * 10).rounded()) % 10)
    }

    private var wholeRange: ClosedRange<Int> { unit == .kg ? 30...200 : 66...440 }

    var body: some View {
        NavigationStack {
            Form {
                HStack(spacing: 0) {
                    Picker("정수", selection: $whole) {
                        ForEach(wholeRange, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Text(".").font(.title2.bold())
                    Picker("소수", selection: $tenth) {
                        ForEach(0..<10, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 70)
                    Text(unit.symbol).font(.title3.bold()).padding(.leading, 6)
                }
                .labelsHidden()
                DatePicker("날짜", selection: $date, in: ...Date())
            }
            .navigationTitle("체중 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        saving = true
                        Task {
                            do {
                                try await HealthData.shared.saveWeight(unit.toKg(Double(whole) + Double(tenth) / 10), at: date)
                                dismiss()
                            } catch {
                                failed = true
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
            .alert("저장하지 못했어요", isPresented: $failed) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("건강 앱에서 세트 카운터의 체중 쓰기 권한을 켜주세요.")
            }
        }
        .presentationDetents([.medium])
    }
}
