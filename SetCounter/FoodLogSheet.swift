import SwiftUI

/// Builds one meal from a food list (or typed-in foods) with a memo, and saves it to
/// Health as dietary energy so other diet apps see it too.
struct FoodLogSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var mealType: MealType
    @State private var date: Date
    @State private var lines: [Line] = []
    @State private var memo = ""
    @State private var category: FoodCategory = FoodCatalog.recent.isEmpty ? .rice : .recent
    @State private var search = ""
    @State private var customName = ""
    @State private var customKcal: Int?
    @State private var saving = false
    @State private var failed = false
    // Bumped when 내 음식 changes so the list re-reads it.
    @State private var customVersion = 0
    @FocusState private var focusedField: Field?

    private let health = HealthData.shared

    private enum Field { case memo, customName, customKcal }

    init(initialDate: Date = Date()) {
        _date = State(initialValue: initialDate)
        _mealType = State(initialValue: MealType.guess(at: initialDate))
    }

    struct Line: Identifiable, Equatable {
        let food: FoodItem
        var amount: Double
        var id: String { food.name }
        var kcal: Double { Double(food.kcal) * amount }
        /// "김밥 1줄 ×2" in the meal log.
        var label: String { amount == 1 ? food.name : "\(food.name) ×\(amount.formatted())" }
    }

    private var total: Int { Int(lines.reduce(0) { $0 + $1.kcal }.rounded()) }

    private var shownFoods: [FoodItem] {
        _ = customVersion
        let query = search.trimmingCharacters(in: .whitespaces).lowercased().filter { !$0.isWhitespace }
        guard !query.isEmpty else { return FoodCatalog.items(in: category) }
        var seen = Set<String>()
        return (FoodCatalog.custom + FoodCatalog.all)
            .filter { $0.name.lowercased().filter { !$0.isWhitespace }.contains(query) && seen.insert($0.name).inserted }
    }

    private var categories: [FoodCategory] {
        _ = customVersion
        return FoodCategory.allCases.filter { !FoodCatalog.items(in: $0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    mealTypePicker
                    DatePicker("먹은 시간", selection: $date, in: ...Date())
                }

                if !lines.isEmpty {
                    Section {
                        ForEach($lines) { $line in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.food.name).font(.subheadline.bold())
                                    Text("\(Int(line.kcal.rounded()).formatted())kcal")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                amountStepper($line)
                            }
                        }
                        .onDelete { lines.remove(atOffsets: $0) }
                    } header: {
                        HStack {
                            Text("담은 음식")
                            Spacer()
                            Text("\(total.formatted())kcal").monospacedDigit()
                        }
                    }
                }

                Section {
                    if search.isEmpty {
                        categoryChips
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                    if shownFoods.isEmpty {
                        Text(search.isEmpty ? "아직 없어요. 아래 '직접 입력'으로 추가하면 여기에 모여요." : "찾는 음식이 없어요. 아래 '직접 입력'으로 추가해 보세요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shownFoods) { food in
                        foodRow(food)
                            .swipeActions {
                                if category == .mine, search.isEmpty {
                                    Button("삭제", role: .destructive) {
                                        FoodCatalog.removeCustom(food)
                                        customVersion += 1
                                    }
                                }
                            }
                    }
                } header: {
                    Text(search.isEmpty ? "음식 고르기" : "검색 결과")
                } footer: {
                    Text("대략적인 1인분 기준이에요. 정확한 숫자는 포장지 영양 정보를 참고하세요.")
                }

                Section {
                    TextField("음식 이름", text: $customName)
                        .focused($focusedField, equals: .customName)
                    HStack {
                        TextField("칼로리", value: $customKcal, format: .number)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .customKcal)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                    Button("담기", systemImage: "plus.circle.fill", action: addCustom)
                        .disabled((customKcal ?? -1) < 0)
                } header: {
                    Text("직접 입력")
                } footer: {
                    Text("이름을 적으면 '내 음식'에 저장돼서 다음부터 바로 고를 수 있어요.")
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "음식 검색")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("식사 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .alert("저장하지 못했어요", isPresented: $failed) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("건강 앱에서 세트 카운터의 식이 에너지 쓰기 권한을 켜주세요.")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Pieces

    private var mealTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(MealType.allCases) { type in
                let isOn = mealType == type
                Button {
                    mealType = type
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: type.systemImage).font(.caption)
                        Text(type.title).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(type.color))
                    .background(isOn ? AnyShapeStyle(type.color) : AnyShapeStyle(type.color.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories) { item in
                    let isOn = category == item
                    Button {
                        category = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline.weight(isOn ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
                            .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func foodRow(_ food: FoodItem) -> some View {
        let count = lines.first { $0.food.name == food.name }?.amount
        return Button {
            add(food)
        } label: {
            HStack {
                Text(food.name).foregroundStyle(Color.primary)
                Spacer()
                Text("\(food.kcal.formatted())kcal")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                if let count {
                    Text("×\(count.formatted())")
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.tint))
                } else {
                    Image(systemName: "plus.circle").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
    }

    /// Half-serving steps; going below half removes the food.
    private func amountStepper(_ line: Binding<Line>) -> some View {
        HStack(spacing: 0) {
            Button {
                if line.wrappedValue.amount <= 0.5 {
                    lines.removeAll { $0.id == line.wrappedValue.id }
                } else {
                    line.wrappedValue.amount -= 0.5
                }
            } label: {
                Image(systemName: line.wrappedValue.amount <= 0.5 ? "trash" : "minus")
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            Text("×\(line.wrappedValue.amount.formatted())")
                .font(.subheadline.bold())
                .monospacedDigit()
                .frame(minWidth: 38)
            Button {
                line.wrappedValue.amount += 0.5
            } label: {
                Image(systemName: "plus").frame(width: 34, height: 30).contentShape(Rectangle())
            }
        }
        .buttonStyle(.borderless)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    /// Memo and save stay in view while scrolling the food list.
    private var saveBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(.secondary)
                TextField("메모 (예: 회식, 삼겹살 2인분이랑 소주 반 병)", text: $memo, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .memo)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            Button(action: save) {
                Text(lines.isEmpty
                     ? String(localized: "음식을 담아 주세요")
                     : String(localized: "\(mealType.title) 저장 · \(total.formatted())kcal"))
                    .font(.headline)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lines.isEmpty || saving)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    // MARK: Actions

    private func add(_ food: FoodItem) {
        if let index = lines.firstIndex(where: { $0.food.name == food.name }) {
            lines[index].amount += 1
        } else {
            lines.append(Line(food: food, amount: 1))
        }
    }

    private func addCustom() {
        guard let kcal = customKcal, kcal >= 0 else { return }
        let name = customName.trimmingCharacters(in: .whitespaces)
        let food = FoodItem(name: name.isEmpty ? String(localized: "직접 입력") : name, kcal: kcal)
        if !name.isEmpty {
            FoodCatalog.addCustom(food)
            customVersion += 1
        }
        add(food)
        customName = ""
        customKcal = nil
        focusedField = nil
    }

    private func save() {
        saving = true
        let foods = lines.map(\.label)
        let eaten = lines.map(\.food)
        Task {
            do {
                try await health.saveMeal(kcal: Double(total), type: mealType, foods: foods, memo: memo, at: date)
                FoodCatalog.noteEaten(eaten)
                dismiss()
            } catch {
                failed = true
            }
            saving = false
        }
    }
}
