import SwiftUI

/// One exercise in a routine part the user arranged themselves.
struct PlanItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var sets: Int
}

/// User-edited routines, keyed by routine part name ("가슴·삼두"), stored as JSON in
/// UserDefaults so backups pick them up with the other settings.
enum RoutinePlans {
    static let key = "routinePlans"

    static func all() -> [String: [PlanItem]] {
        guard let data = UserDefaults.standard.string(forKey: key)?.data(using: .utf8),
              let plans = try? JSONDecoder().decode([String: [PlanItem]].self, from: data) else { return [:] }
        return plans
    }

    /// nil means "use the automatic suggestion".
    static func plan(for part: String) -> [PlanItem]? {
        all()[part]
    }

    static func save(_ items: [PlanItem]?, for part: String) {
        var plans = all()
        plans[part] = items
        guard let data = try? JSONEncoder().encode(plans) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: key)
    }
}

/// Add, remove, reorder, and set the number of sets for a part's exercises.
struct RoutinePlanEditor: View {
    let part: String

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PlanItem]
    @State private var showingPicker = false
    private let isCustom: Bool

    init(part: String, suggestions: [RoutineSuggestion]) {
        self.part = part
        let saved = RoutinePlans.plan(for: part)
        isCustom = saved != nil
        _items = State(initialValue: saved ?? suggestions.map { PlanItem(name: $0.exercise, sets: $0.sets) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if items.isEmpty {
                        Text("아래 '운동 추가'로 루틴을 채워 보세요.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($items) { $item in
                        Stepper(value: $item.sets, in: 1...10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.body.bold())
                                Text("\(item.sets)세트").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("\(part) 운동")
                } footer: {
                    Text("☰를 끌어 순서를 바꾸고, 빨간 버튼으로 뺄 수 있어요. 무게와 횟수는 지난 기록을 보고 자동으로 잡아요.")
                }

                Section {
                    Button("운동 추가", systemImage: "plus.circle.fill") { showingPicker = true }
                }

                if isCustom {
                    Section {
                        Button("추천 루틴으로 되돌리기", role: .destructive) {
                            RoutinePlans.save(nil, for: part)
                            dismiss()
                        }
                    }
                }
            }
            // Always in edit mode: reorder handles and delete buttons without an extra tap.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("루틴 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        RoutinePlans.save(items, for: part)
                        dismiss()
                    }
                    .disabled(items.isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(title: "운동 추가", preferred: Coach.muscles(in: part)) { name in
                    if !items.contains(where: { $0.name == name }) {
                        items.append(PlanItem(name: name, sets: 3))
                    }
                }
            }
        }
    }
}
