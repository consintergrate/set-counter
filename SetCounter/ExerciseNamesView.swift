import SwiftData
import SwiftUI

/// Rename, merge, and assign a body part to the exercises found in the records.
struct ExerciseNamesView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Query private var profiles: [ExerciseProfile]
    @Environment(\.modelContext) private var modelContext

    @State private var renaming: String?
    @State private var newName = ""
    @State private var merging: String?

    private struct Entry: Identifiable {
        let name: String
        let count: Int
        let lastDate: Date
        var id: String { name }
    }

    private var entries: [Entry] {
        Dictionary(grouping: records.filter { !$0.exercise.isEmpty }, by: \.exercise)
            .map { Entry(name: $0.key, count: $0.value.count, lastDate: $0.value.map(\.date).max() ?? .distantPast) }
            .sorted { $0.lastDate > $1.lastDate }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("아직 운동 기록이 없어요", systemImage: "dumbbell", description: Text("운동을 기록하면 여기서 이름과 부위를 관리할 수 있어요."))
            }
            Section {
                ForEach(entries) { entry in
                    row(entry)
                }
            } footer: {
                Text("부위는 통계의 부위별 균형 분석에 쓰여요. 운동 이름을 보고 자동으로 정해두었고, 직접 바꿀 수 있어요.")
            }
        }
        .navigationTitle("운동 이름 관리")
        .alert("이름 바꾸기", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("새 이름", text: $newName)
            Button("취소", role: .cancel) { renaming = nil }
            Button("바꾸기") {
                if let renaming { rename(renaming, to: newName) }
                renaming = nil
            }
        } message: {
            Text("같은 이름의 운동이 이미 있으면 기록이 하나로 합쳐져요.")
        }
        .confirmationDialog(
            merging.map { String(localized: "'\($0)'을(를) 어느 운동으로 합칠까요?") } ?? "",
            isPresented: Binding(get: { merging != nil }, set: { if !$0 { merging = nil } }),
            titleVisibility: .visible
        ) {
            if let source = merging {
                ForEach(entries.filter { $0.name != source }) { target in
                    Button(target.name) { rename(source, to: target.name) }
                }
            }
        } message: {
            Text("기록이 모두 고른 운동 이름으로 옮겨져요.")
        }
    }

    private func row(_ entry: Entry) -> some View {
        let muscle = Muscle.lookup(entry.name, in: profiles)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.headline)
                Text("\(entry.count)개 기록 · 마지막 \(entry.lastDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("부위", selection: Binding(get: { muscle }, set: { setMuscle($0, for: entry.name) })) {
                    ForEach(Muscle.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Button("이름 바꾸기", systemImage: "pencil") {
                    newName = entry.name
                    renaming = entry.name
                }
                if entries.count > 1 {
                    Button("다른 운동과 합치기", systemImage: "arrow.triangle.merge") { merging = entry.name }
                }
            } label: {
                Text(muscle.title)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
            }
        }
    }

    private func setMuscle(_ muscle: Muscle, for name: String) {
        if let profile = profiles.first(where: { $0.name == name }) {
            profile.muscleRaw = muscle.rawValue
        } else {
            modelContext.insert(ExerciseProfile(name: name, muscle: muscle))
        }
    }

    /// Moves every record (and the body part, if the target has none) to `newName`.
    private func rename(_ oldName: String, to newName: String) {
        let target = newName.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, target != oldName else { return }
        for record in records where record.exercise == oldName {
            record.exercise = target
        }
        if let old = profiles.first(where: { $0.name == oldName }) {
            if profiles.contains(where: { $0.name == target }) {
                modelContext.delete(old)
            } else {
                old.name = target
            }
        }
        if UserDefaults.standard.string(forKey: "exercise") == oldName {
            UserDefaults.standard.set(target, forKey: "exercise")
        }
    }
}
