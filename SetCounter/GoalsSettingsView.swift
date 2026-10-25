import SwiftUI

struct GoalsSettingsView: View {
    @AppStorage(Goals.goalWeightKey) private var goalWeight = 68.0
    @AppStorage(Goals.weeklyLossKey) private var weeklyLoss = 0.5
    @AppStorage(Goals.stepKey) private var stepGoal = 8000
    @AppStorage(Goals.activeKey) private var activeGoal = 400
    @AppStorage(Goals.exerciseKey) private var exerciseGoal = 30
    @AppStorage(Goals.cardioKey) private var cardioGoal = 150
    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue
    // Read so the intake estimate below updates when the profile changes.
    @AppStorage("bodyWeight") private var bodyWeight = 70.0
    @AppStorage(Goals.heightKey) private var heightCm = 172.0

    private let health = HealthData.shared
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    private var goalWeightValues: [Double] {
        unit == .kg ? stride(from: 35.0, through: 180, by: 0.5).map { $0 } : stride(from: 77.0, through: 400, by: 1).map { $0 }
    }

    private var displayGoalWeight: Binding<Double> {
        Binding(
            get: {
                let step = unit == .kg ? 0.5 : 1
                let value = (unit.fromKg(goalWeight) / step).rounded() * step
                return min(max(value, goalWeightValues.first ?? value), goalWeightValues.last ?? value)
            },
            set: { goalWeight = unit.toKg($0) }
        )
    }

    var body: some View {
        let _ = (bodyWeight, heightCm)
        let target = Goals.saved.intakeTarget(profile: .saved)
        Form {
            Section {
                WheelPickerRow(title: "목표 체중", values: goalWeightValues, selection: displayGoalWeight) {
                    "\($0.formatted(.number.precision(.fractionLength(unit == .kg ? 1 : 0))))\(unit.symbol)"
                }
                Picker("감량 속도", selection: $weeklyLoss) {
                    Text("유지").tag(0.0)
                    Text("주 0.25kg").tag(0.25)
                    Text("주 0.5kg").tag(0.5)
                    Text("주 0.75kg").tag(0.75)
                }
                LabeledContent("하루 권장 섭취") {
                    Text("\(Int(target).formatted()) kcal").bold().monospacedDigit()
                }
            } header: {
                Text("체중")
            } footer: {
                Text("키·체중·나이·성별로 기초대사량을 계산하고, 감량 속도만큼 덜 먹도록 잡아요(1kg ≈ 7,700kcal). 운동으로 쓴 칼로리는 그날 더 먹을 수 있는 양에 더해져요. 건강을 위해 남성 1,500kcal, 여성 1,200kcal 아래로는 잡지 않아요.")
            }

            Section("하루 활동 목표") {
                WheelPickerRow(title: "걸음", values: Array(stride(from: 2000, through: 20000, by: 500)), selection: $stepGoal) {
                    String(localized: "\($0.formatted())보")
                }
                WheelPickerRow(title: "활동 칼로리", values: Array(stride(from: 100, through: 1500, by: 50)), selection: $activeGoal) {
                    "\($0.formatted()) kcal"
                }
                WheelPickerRow(title: "운동 시간", values: Array(stride(from: 10, through: 120, by: 5)), selection: $exerciseGoal) {
                    String(localized: "\($0)분")
                }
            }

            Section {
                WheelPickerRow(title: "주간 유산소", values: Array(stride(from: 30, through: 600, by: 30)), selection: $cardioGoal) {
                    String(localized: "주 \($0)분")
                }
            } header: {
                Text("유산소")
            } footer: {
                Text("세계보건기구(WHO)는 주 150분 이상의 중간 강도 유산소 운동을 권장해요. 나이키 런 클럽, 피트니스 앱 등에서 건강 앱에 저장한 러닝·걷기·사이클이 자동으로 합산돼요.")
            }

            Section {
                Button("건강 앱 권한 확인", systemImage: "heart.text.square") {
                    Task { await health.requestAuthorization() }
                }
            } footer: {
                Text("걸음 수, 활동 칼로리, 체중, 먹은 칼로리, 다른 앱의 운동을 건강 앱에서 읽어와요. 이미 거절했다면 iPhone 설정 → 건강 → 데이터 접근 및 기기 → 세트 카운터에서 켤 수 있어요.")
            }
        }
        .navigationTitle("다이어트 · 활동 목표")
    }
}
