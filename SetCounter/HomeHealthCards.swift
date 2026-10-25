import SwiftUI

/// Shared look for the home screen's white cards.
private extension View {
    func homeCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct CardHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, systemImage: String) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

/// Asks once for Health access; everything diet-related reads from there.
struct HealthConnectCard: View {
    let health: HealthData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "건강 앱 연결", systemImage: "heart.text.square.fill")
            Text("걸음 수, 활동 칼로리, 체중, 먹은 칼로리, 나이키 런 클럽 같은 다른 앱의 러닝 기록을 가져와 하루 칼로리와 유산소 목표를 계산해요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await health.requestAuthorization() }
            } label: {
                Text("연결하기")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .homeCard()
    }
}

/// The assistant's few lines for today.
struct CoachCard: View {
    let tips: [CoachTip]
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "오늘의 코치", systemImage: "sparkles") {
                Button("주간 리포트", action: onReport)
                    .font(.subheadline)
            }
            ForEach(tips) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tip.kind == .routine ? AnyShapeStyle(.tint) : AnyShapeStyle(tip.color))
                        .frame(width: 32, height: 32)
                        .background((tip.kind == .routine ? Color.accentColor : tip.color).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title).font(.subheadline.bold())
                        Text(tip.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .homeCard()
    }
}

/// Today's suggested exercises; tapping one fills in the setup screen.
struct RecommendedRoutineCard: View {
    let part: String
    let suggestions: [RoutineSuggestion]
    let onSelect: (RoutineSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(title: "\(part) 추천 루틴", systemImage: "list.bullet.clipboard")
                .padding(.bottom, 6)
            ForEach(suggestions) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.doneToday ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.doneToday ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.exercise)
                                .font(.subheadline.bold())
                                .strikethrough(item.doneToday)
                            Text("\(formatWeight(item.weight)) × \(item.reps)회 × \(item.sets)세트")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !item.note.isEmpty {
                            Text(item.note)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(item.isNew ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120, alignment: .trailing)
                        }
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("지난 기록에서 12회를 채운 운동은 무게를, 8회 이상이면 횟수를 하나씩 올려 잡았어요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .homeCard()
    }
}

/// Move, exercise, and steps rings against the daily goals.
struct ActivityRingsCard: View {
    let health: HealthData
    let goals: Goals

    private struct Ring: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let value: String
        let progress: Double
        let color: Color
    }

    private var rings: [Ring] {
        [
            Ring(id: 0, title: "활동", value: "\(Int(health.todayActive).formatted())/\(goals.activeCalories.formatted())kcal",
                 progress: health.todayActive / Double(max(goals.activeCalories, 1)), color: .pink),
            Ring(id: 1, title: "운동", value: String(localized: "\(Int(health.todayExerciseMinutes))/\(goals.exerciseMinutes)분"),
                 progress: health.todayExerciseMinutes / Double(max(goals.exerciseMinutes, 1)), color: .green),
            Ring(id: 2, title: "걸음", value: "\(Int(health.todaySteps).formatted())/\(goals.steps.formatted())",
                 progress: health.todaySteps / Double(max(goals.steps, 1)), color: .cyan),
        ]
    }

    var body: some View {
        let rings = rings
        HStack(spacing: 20) {
            ZStack {
                ForEach(rings) { ring in
                    let size = 108 - CGFloat(ring.id) * 30
                    Circle()
                        .stroke(ring.color.opacity(0.18), lineWidth: 12)
                        .frame(width: size, height: size)
                    Circle()
                        .trim(from: 0, to: min(ring.progress, 1))
                        .stroke(ring.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size, height: size)
                }
            }
            .frame(width: 120, height: 120)
            .animation(.easeOut(duration: 0.6), value: health.lastRefresh)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(rings) { ring in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ring.title).font(.caption.weight(.semibold)).foregroundStyle(ring.color)
                        Text(ring.value).font(.subheadline.bold()).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
        }
        .homeCard()
    }
}

/// Goal − food + exercise = remaining, the way diet apps show it.
struct CalorieCard: View {
    let health: HealthData
    let goals: Goals
    let profile: BodyProfile
    let onAddFood: () -> Void

    var body: some View {
        let budget = CalorieBudget(goals: goals, profile: profile, health: health)
        let allowance = budget.target + budget.exercise
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "오늘의 칼로리", systemImage: "flame.fill") {
                Button("식사 추가", systemImage: "plus", action: onAddFood)
                    .font(.subheadline.weight(.semibold))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Int(abs(budget.remaining)).formatted())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(budget.remaining < 0 ? .red : .primary)
                Text(budget.remaining < 0 ? "kcal 초과" : "kcal 남음")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: min(budget.eaten, allowance), total: max(allowance, 1))
                .tint(budget.remaining < 0 ? .red : .orange)

            HStack {
                term("목표", budget.target)
                Text("−").foregroundStyle(.secondary)
                term("음식", budget.eaten)
                Text("+").foregroundStyle(.secondary)
                term("운동", budget.exercise)
            }

            NavigationLink {
                WeightView()
            } label: {
                HStack {
                    Image(systemName: "scalemass.fill").foregroundStyle(.tint)
                    if let latest = health.latestWeight {
                        Text("체중 \(formatMass(latest.kg))")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    } else {
                        Text("체중 기록하기").font(.subheadline.bold())
                    }
                    if Goals.hasGoalWeight {
                        Text("목표 \(formatMass(goals.goalWeight))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("목표 정하기")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .homeCard()
    }

    private func term(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(Int(value).formatted()).font(.subheadline.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A running or fitness app that writes its workouts to Health.
struct FitnessAppLink: Identifiable {
    let name: LocalizedStringKey
    let systemImage: String
    let color: Color
    /// Tried in order; the first one the system can open wins.
    let schemes: [String]
    let appStoreID: String?
    var id: String { schemes.first ?? "" }

    static let all: [FitnessAppLink] = [
        FitnessAppLink(name: "나이키 런", systemImage: "figure.run", color: .primary,
                       schemes: ["nikerunclub://", "nikeplus://"], appStoreID: "387771637"),
        FitnessAppLink(name: "스트라바", systemImage: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath.fill",
                       color: .orange, schemes: ["strava://"], appStoreID: "426826309"),
        FitnessAppLink(name: "피트니스", systemImage: "circle.circle", color: .green,
                       schemes: ["fitnessapp://"], appStoreID: "1208224953"),
        FitnessAppLink(name: "건강", systemImage: "heart.fill", color: .pink,
                       schemes: ["x-apple-health://"], appStoreID: nil),
    ]

    @MainActor
    func open() async {
        for scheme in schemes {
            if let url = URL(string: scheme), await UIApplication.shared.open(url) { return }
        }
        if let appStoreID, let url = URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)") {
            await UIApplication.shared.open(url)
        }
    }
}

/// This week's cardio from other apps, plus shortcuts to start a run there.
struct CardioCard: View {
    let health: HealthData
    let goals: Goals

    var body: some View {
        let week = health.cardio(inWeekOf: Date()).filter(\.isCardio)
        let minutes = Int(health.cardioMinutes(inWeekOf: Date()))
        let distance = week.reduce(0) { $0 + $1.distance }
        let goal = max(goals.cardioWeeklyMinutes, 1)
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "이번 주 유산소", systemImage: "figure.run") {
                Text("\(minutes)/\(goals.cardioWeeklyMinutes)분")
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .foregroundStyle(minutes >= goal ? .green : .teal)
            }
            ProgressView(value: Double(min(minutes, goal)), total: Double(goal))
                .tint(minutes >= goal ? .green : .teal)
            HStack(spacing: 0) {
                MiniStat(title: "횟수", value: String(localized: "cardio.sessions", defaultValue: "\(week.count)회"))
                MiniStat(title: "거리", value: formatDistance(distance))
                MiniStat(title: "칼로리", value: "\(Int(week.reduce(0) { $0 + $1.energy }).formatted())kcal")
            }

            if let last = health.cardio.first(where: \.isCardio) {
                HStack(spacing: 12) {
                    Image(systemName: last.systemImage)
                        .foregroundStyle(.teal)
                        .frame(width: 32, height: 32)
                        .background(Color.teal.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(last.title) · \(last.summary)").font(.subheadline.bold()).monospacedDigit()
                        Text("\(last.start.formatted(.relative(presentation: .named))) · \(last.source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(FitnessAppLink.all) { app in
                    Button {
                        Task { await app.open() }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: app.systemImage)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(app.color)
                                .frame(height: 24)
                            Text(app.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("다른 앱에서 운동을 마치면 건강 앱을 거쳐 여기에 자동으로 합산돼요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .homeCard()
    }
}
