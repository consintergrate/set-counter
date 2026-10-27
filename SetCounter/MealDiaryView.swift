import SwiftUI

/// One logged meal: type and time, what was eaten, the memo, and calories.
struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: meal.type.systemImage)
                .foregroundStyle(meal.type.color)
                .frame(width: 30, height: 30)
                .background(meal.type.color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meal.type.title).font(.subheadline.bold())
                    Text(meal.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(meal.kcal.rounded()).formatted())kcal")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                }
                Text(meal.foods.isEmpty ? (meal.isOwn ? String(localized: "음식 이름 없이 기록") : meal.source) : meal.foods)
                    .font(.subheadline)
                    .foregroundStyle(meal.foods.isEmpty ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !meal.memo.isEmpty {
                    Label(meal.memo, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Day-by-day meal log with totals against the day's allowance.
struct MealDiaryView: View {
    @State private var dayOffset = 0
    @State private var adding = false
    @State private var deleteFailed = false
    @State private var paywall: ProFeature?

    private let health = HealthData.shared
    private var calendar: Calendar { .current }

    private var day: Date {
        calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        let day = day
        let meals = health.meals(on: day)
        let eaten = meals.reduce(0) { $0 + $1.kcal }
        let allowance = Goals.saved.intakeTarget(profile: .saved) + (health.dailyActive[day] ?? 0)
        List {
            Section {
                PeriodSwitcher(
                    title: day.formatted(.dateTime.month(.wide).day().weekday(.wide)),
                    subtitle: dayOffset == 0 ? String(localized: "오늘") : dayOffset == -1 ? String(localized: "어제") : nil,
                    canGoBack: dayOffset > -27,
                    canGoForward: dayOffset < 0,
                    // Today is free; earlier days are Pro.
                    backIsLocked: !ProStore.shared.isPro,
                    onBack: { if ProStore.shared.isPro { dayOffset -= 1 } else { paywall = .diet } },
                    onForward: { dayOffset += 1 }
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(eaten).formatted())").font(.title.bold()).monospacedDigit()
                        Text("/ \(Int(allowance).formatted())kcal").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Text(eaten > allowance
                             ? String(localized: "\(Int(eaten - allowance).formatted())kcal 초과")
                             : String(localized: "\(Int(allowance - eaten).formatted())kcal 남음"))
                            .font(.subheadline.bold())
                            .foregroundStyle(eaten > allowance ? .red : .green)
                    }
                    ProgressView(value: min(eaten, allowance), total: max(allowance, 1))
                        .tint(eaten > allowance ? .red : .orange)
                }
            }

            if meals.isEmpty {
                Section {
                    Text("이 날은 기록한 식사가 없어요.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(MealType.allCases) { type in
                let typed = meals.filter { $0.type == type }
                if !typed.isEmpty {
                    Section {
                        ForEach(typed) { meal in
                            MealRow(meal: meal)
                                // No full-swipe delete: removing Health data takes a deliberate tap.
                                .swipeActions(allowsFullSwipe: false) {
                                    if meal.isOwn {
                                        Button("삭제", role: .destructive) { delete(meal) }
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(type.title)
                            Spacer()
                            Text("\(Int(typed.reduce(0) { $0 + $1.kcal }).formatted())kcal").monospacedDigit()
                        }
                    }
                }
            }

            Section {
            } footer: {
                Text("세트 카운터에서 기록한 식사는 왼쪽으로 밀어서 지울 수 있어요. 다른 앱의 기록은 그 앱이나 건강 앱에서 고쳐 주세요.")
            }
        }
        .navigationTitle("식단 기록")
        .proPaywall($paywall)
        .toolbar {
            Button("식사 추가", systemImage: "plus") { adding = true }
        }
        .sheet(isPresented: $adding) {
            // A past day opens at its lunchtime so the meal lands on that day.
            FoodLogSheet(initialDate: dayOffset == 0 ? Date() : calendar.date(byAdding: .hour, value: 12, to: day) ?? day)
        }
        .refreshable { await health.refresh() }
        .alert("지우지 못했어요", isPresented: $deleteFailed) {
            Button("확인", role: .cancel) {}
        }
    }

    private func delete(_ meal: MealEntry) {
        Task {
            do { try await health.deleteMeal(meal) } catch { deleteFailed = true }
        }
    }
}
