import SwiftUI

/// Quick calorie entry, saved to Health as dietary energy so other diet apps see it too.
struct FoodLogSheet: View {
    @State private var kcal = 0
    @State private var date = Date()
    @State private var saving = false
    @State private var failed = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let health = HealthData.shared

    /// Rough values for common Korean meals and snacks; tapping adds to the total.
    private static let presets: [(name: LocalizedStringKey, kcal: Int)] = [
        ("공깃밥", 300), ("닭가슴살", 120), ("계란 1개", 75), ("바나나", 90),
        ("프로틴 쉐이크", 130), ("김밥 1줄", 450), ("라면", 500), ("치킨 1조각", 250),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0", value: $kcal, format: .number)
                            .keyboardType(.numberPad)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .focused($fieldFocused)
                        Text("kcal").font(.title3.bold()).foregroundStyle(.secondary)
                        if kcal > 0 {
                            Button("지우기", systemImage: "xmark.circle.fill") { kcal = 0 }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("먹은 시간", selection: $date, in: ...Date())
                } footer: {
                    Text("오늘 먹은 양: \(Int(health.todayEaten).formatted())kcal")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(Self.presets.indices, id: \.self) { index in
                            let preset = Self.presets[index]
                            Button {
                                kcal += preset.kcal
                            } label: {
                                VStack(spacing: 2) {
                                    Text(preset.name).font(.subheadline.bold())
                                    Text("+\(preset.kcal)kcal").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("빠른 추가")
                } footer: {
                    Text("대략적인 값이에요. 정확한 숫자는 포장지 영양 정보를 참고하세요.")
                }
            }
            .navigationTitle("식사 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        saving = true
                        Task {
                            do {
                                try await health.saveFood(Double(kcal), at: date)
                                dismiss()
                            } catch {
                                failed = true
                            }
                            saving = false
                        }
                    }
                    .disabled(kcal <= 0 || saving)
                }
            }
            .alert("저장하지 못했어요", isPresented: $failed) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("건강 앱에서 세트 카운터의 식이 에너지 쓰기 권한을 켜주세요.")
            }
        }
        .presentationDetents([.large])
    }
}
