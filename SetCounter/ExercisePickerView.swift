import SwiftData
import SwiftUI

/// Searchable exercise list: recent ones, the user's own, then the built-in list by
/// muscle. Typing a name that isn't listed offers to add it. Pushed onto the
/// caller's navigation stack; picking pops back.
struct ExercisePickerView: View {
    var title: LocalizedStringKey = "운동 선택"
    /// Muscles listed first, e.g. today's routine part.
    var preferred: [Muscle] = []
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Query(sort: \ExerciseProfile.name) private var profiles: [ExerciseProfile]

    @State private var search = ""
    @State private var filter: Muscle?
    @State private var newMuscle = Muscle.other

    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespaces) }

    private func matches(_ name: String) -> Bool {
        trimmedSearch.isEmpty || ExerciseLibrary.normalized(name).contains(ExerciseLibrary.normalized(trimmedSearch))
    }

    private func muscle(of name: String) -> Muscle { Muscle.lookup(name, in: profiles) }

    private var recent: [String] {
        var seen = Set<String>()
        return records.map(\.exercise).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    /// Names the user logged or added that aren't in the built-in list.
    private var mine: [String] {
        let names = Set(records.map(\.exercise)).union(profiles.map(\.name)).filter { !$0.isEmpty }
        return names.filter { ExerciseLibrary.find($0) == nil }.sorted()
    }

    /// The user's own spelling of listed exercises ("인클라인 덤벨프레스"), so picking
    /// from the list doesn't split their history under a second name.
    private var ownSpelling: [String: String] {
        var spelling: [String: String] = [:]
        for name in records.map(\.exercise) where !name.isEmpty {
            let key = ExerciseLibrary.normalized(name)
            if spelling[key] == nil { spelling[key] = name }
        }
        return spelling
    }

    private var orderedMuscles: [Muscle] {
        preferred + (Muscle.tracked + [.other]).filter { !preferred.contains($0) }
    }

    private var hasExactMatch: Bool {
        let key = ExerciseLibrary.normalized(trimmedSearch)
        return (ExerciseLibrary.all.map(\.name) + mine).contains { ExerciseLibrary.normalized($0) == key }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(nil)
                        ForEach(orderedMuscles) { chip($0) }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if !trimmedSearch.isEmpty, !hasExactMatch {
                Section {
                    Button {
                        add(trimmedSearch)
                    } label: {
                        Label("‘\(trimmedSearch)’ 추가", systemImage: "plus.circle.fill")
                    }
                    Picker("부위", selection: $newMuscle) {
                        ForEach(Muscle.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("목록에 없는 운동은 이렇게 추가해 두면 다음부터 '내 운동'에 나와요.")
                }
            }

            if filter == nil, trimmedSearch.isEmpty, !recent.isEmpty {
                Section("최근") {
                    ForEach(recent, id: \.self) { row($0) }
                }
            }

            let ownNames = mine.filter { matches($0) && (filter == nil || muscle(of: $0) == filter) }
            if !ownNames.isEmpty {
                Section("내 운동") {
                    ForEach(ownNames, id: \.self) { name in
                        row(name)
                            .swipeActions {
                                // Only names the user added and never logged can go.
                                if let profile = profiles.first(where: { $0.name == name }),
                                   !records.contains(where: { $0.exercise == name }) {
                                    Button("삭제", role: .destructive) {
                                        modelContext.delete(profile)
                                        try? modelContext.save()
                                    }
                                }
                            }
                    }
                }
            }

            let spelling = ownSpelling
            ForEach(orderedMuscles.filter { filter == nil || $0 == filter }) { muscle in
                let items = ExerciseLibrary.exercises(for: muscle)
                    .map { spelling[ExerciseLibrary.normalized($0.name)] ?? $0.name }
                    .filter(matches)
                if !items.isEmpty {
                    Section(muscle.title) {
                        ForEach(items, id: \.self) { row($0, showMuscle: false) }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "운동 검색 또는 새 이름")
        .onChange(of: search) { _, text in newMuscle = Muscle.guess(for: text) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ muscle: Muscle?) -> some View {
        let isOn = filter == muscle
        return Button {
            filter = muscle
        } label: {
            Text(muscle?.title ?? String(localized: "전체"))
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
                .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    private func row(_ name: String, showMuscle: Bool = true) -> some View {
        Button {
            onPick(name)
            dismiss()
        } label: {
            HStack {
                Text(name).foregroundStyle(Color.primary)
                Spacer()
                if showMuscle {
                    Text(muscle(of: name).title).font(.caption).foregroundStyle(Color.secondary)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func add(_ name: String) {
        if !profiles.contains(where: { $0.name == name }) {
            modelContext.insert(ExerciseProfile(name: name, muscle: newMuscle))
            try? modelContext.save()
        }
        onPick(name)
        dismiss()
    }
}
