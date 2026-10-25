import SwiftData
import SwiftUI

/// First screen: the coach's tips, today's routine with a start button, the day's
/// activity and calories, this week's progress, and what happened lately.
/// Workout setup opens as a sheet from here.
struct HomeView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Query private var profiles: [ExerciseProfile]
    @AppStorage(Routine.namesKey) private var routineRaw = Routine.defaultRaw
    @AppStorage("weeklyGoal") private var weeklyGoal = 4
    @AppStorage("accent") private var accent = AccentChoice.blue.rawValue
    @AppStorage("routineOverrideDay") private var overrideDay = 0.0
    @AppStorage("routineOverrideIndex") private var overrideIndex = 0

    @State private var showingSetup = false
    /// Held while the setup sheet closes, then presented full screen.
    @State private var pendingSession: WorkoutSession?
    @State private var session: WorkoutSession?
    @State private var showingFood = false
    @State private var showingGuide = false
    // Snapshots of the settings, refreshed whenever a default changes (goals, body weight…).
    @State private var goals = Goals.saved
    @State private var profile = BodyProfile.saved

    private let health = HealthData.shared
    /// Diet cards wait for the first Health read so they don't flash zeros.
    private var hasHealth: Bool { health.isAvailable && !health.needsAuthorization && health.lastRefresh != nil }

    private var calendar: Calendar { .current }
    private var accentColor: Color { (AccentChoice(rawValue: accent) ?? .blue).color }
    private var routineNames: [String] { Routine.names(from: routineRaw) }

    // Reads the override keys so the card refreshes when today's part is changed.
    private var todayIndex: Int {
        _ = (overrideDay, overrideIndex)
        return Routine.todayIndex(count: routineNames.count, records: records)
    }

    private var todayName: String { routineNames[todayIndex] }
    private var todayRecords: [WorkoutRecord] { records.filter { calendar.isDateInToday($0.date) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greeting
                    if health.isAvailable, health.needsAuthorization {
                        HealthConnectCard(health: health)
                    }
                    CoachCard(
                        tips: Coach.tips(records: records, profiles: profiles, health: health, todayPart: todayName,
                                         goals: goals, profile: profile),
                        onReport: { AppRouter.shared.showingWeeklyReport = true }
                    )
                    TodayCard(
                        splitLabel: routineNames.count == 1
                            ? String(localized: "무분할 루틴")
                            : String(localized: "\(routineNames.count)분할 · \(todayIndex + 1)일차"),
                        todayName: todayName,
                        lastTime: lastSession(for: todayName),
                        doneToday: todayRecords,
                        color: accentColor,
                        routineNames: routineNames,
                        onPick: { index in
                            overrideDay = calendar.startOfDay(for: Date()).timeIntervalSince1970
                            overrideIndex = index
                        },
                        onStart: { showingSetup = true },
                        onGuide: { showingGuide = true }
                    )
                    let suggestions = Coach.recommendedRoutine(for: todayName, records: records, profiles: profiles)
                    if !suggestions.isEmpty {
                        RecommendedRoutineCard(part: todayName, suggestions: suggestions, onSelect: prefill)
                    }
                    if hasHealth {
                        ActivityRingsCard(health: health, goals: goals)
                        CalorieCard(health: health, goals: goals, profile: profile) { showingFood = true }
                        CardioCard(health: health, goals: goals)
                    }
                    WeekCard(records: records, goal: weeklyGoal, color: accentColor)
                    recentSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSetup, onDismiss: {
                if let pendingSession {
                    session = pendingSession
                    self.pendingSession = nil
                }
            }) {
                SetupView { started in
                    pendingSession = started
                    showingSetup = false
                }
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $session) { session in
                WorkoutView(session: session)
            }
            .sheet(isPresented: $showingFood) {
                FoodLogSheet()
            }
            .sheet(isPresented: $showingGuide) {
                OnboardingView { showingGuide = false }
            }
            .refreshable { await health.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                goals = .saved
                profile = .saved
            }
        }
    }

    /// Fills the setup screen with a suggested exercise and opens it.
    private func prefill(_ item: RoutineSuggestion) {
        let defaults = UserDefaults.standard
        defaults.set(item.exercise, forKey: "exercise")
        defaults.set(item.weight, forKey: "weight")
        defaults.set(item.reps, forKey: "reps")
        defaults.set(item.sets, forKey: "totalSets")
        showingSetup = true
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(greetingText)
                .font(.largeTitle.bold())
        }
        .padding(.top, 8)
    }

    private var greetingText: String {
        switch calendar.component(.hour, from: Date()) {
        case 5..<12: String(localized: "좋은 아침이에요")
        case 12..<18: String(localized: "오늘도 힘내봐요")
        default: String(localized: "좋은 저녁이에요")
        }
    }

    /// The most recent day this routine part was trained, one line per exercise.
    private func lastSession(for part: String) -> [String] {
        guard let latest = records.first(where: { $0.routineName == part }) else { return [] }
        let day = records.filter { $0.routineName == part && calendar.isDate($0.date, inSameDayAs: latest.date) }
        var seen = Set<String>()
        return day.reversed().filter { !$0.exercise.isEmpty && seen.insert($0.exercise).inserted }.prefix(3).map {
            String(localized: "\($0.exercise) \(formatWeight($0.bestWeight)) × \($0.reps)")
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let recentPRs = ExerciseBest.all(in: records).filter(\.isRecent).prefix(3)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("최근 기록").font(.title3.bold())
                Spacer()
                if !records.isEmpty {
                    NavigationLink("전체 보기") { HistoryView() }
                        .font(.subheadline)
                }
            }

            if records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text("첫 운동을 기록해보세요").font(.headline)
                    Text("운동 시작을 누르고 세트를 마칠 때마다 한 번만 누르면 돼요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentPRs)) { item in
                        NavigationLink {
                            ExerciseDetailView(name: item.name)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.orange)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.subheadline.bold())
                                    Text("신기록 \(item.best.weight > 0 ? formatWeight(item.best.weight) : String(localized: "\(item.best.reps)회"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 40)
                    }
                    ForEach(records.prefix(4)) { record in
                        NavigationLink {
                            RecordEditorView(record: record)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(spacing: 0) {
                                    // Bare number: the Korean day format adds "일" and wraps.
                                    Text("\(calendar.component(.day, from: record.date))")
                                        .font(.subheadline.bold())
                                        .monospacedDigit()
                                    Text(record.date.formatted(.dateTime.weekday(.abbreviated)))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.exercise.isEmpty ? String(localized: "운동") : record.exercise)
                                        .font(.subheadline.bold())
                                    Text(setsSummary(record.setValues)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if record.id != records.prefix(4).last?.id { Divider().padding(.leading, 40) }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

/// The hero card: today's part, what was done last time, and the start button.
private struct TodayCard: View {
    let splitLabel: String
    let todayName: String
    let lastTime: [String]
    let doneToday: [WorkoutRecord]
    let color: Color
    let routineNames: [String]
    let onPick: (Int) -> Void
    let onStart: () -> Void
    /// Reopens the first-launch guide, right next to the button it explains.
    let onGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(splitLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if routineNames.count > 1 {
                    Menu {
                        ForEach(routineNames.indices, id: \.self) { index in
                            Button("\(index + 1)일차 · \(routineNames[index])") { onPick(index) }
                        }
                    } label: {
                        Label("바꾸기", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("오늘은")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                Text(String(localized: "\(todayName) 데이"))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            if !doneToday.isEmpty {
                let sets = doneToday.reduce(0) { $0 + $1.sets }
                Label("오늘 \(doneToday.count)개 운동 · \(sets)세트 완료", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            } else if !lastTime.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("지난번")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach(lastTime, id: \.self) { line in
                        Text(line).font(.subheadline).foregroundStyle(.white).monospacedDigit()
                    }
                }
            }

            Button(action: onStart) {
                Label(doneToday.isEmpty ? "운동 시작" : "이어서 운동하기", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)

            Button(action: onGuide) {
                Label("세트 카운트 사용법", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [color, color.mix(with: .black, by: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: color.opacity(0.3), radius: 16, y: 8)
    }
}

/// Weekly goal ring, streak, and one dot per day of this week.
private struct WeekCard: View {
    let records: [WorkoutRecord]
    let goal: Int
    let color: Color

    private var calendar: Calendar { .current }

    private var weekDays: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Consecutive weeks with at least one workout, not counting an empty current week against it.
    private var weekStreak: Int {
        let weeks = Set(records.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        if !weeks.contains(week) { week = calendar.date(byAdding: .weekOfYear, value: -1, to: week) ?? week }
        var count = 0
        while weeks.contains(week) {
            count += 1
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        }
        return count
    }

    var body: some View {
        let workoutDays = Set(records.map { calendar.startOfDay(for: $0.date) })
        let done = Routine.weeklyDays(records: records)
        let progress = Double(min(done, goal)) / Double(max(goal, 1))
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(color.opacity(0.15), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(done >= goal ? Color.green : color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(done)").font(.title2.bold()).monospacedDigit()
                        Text("/\(goal)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(done >= goal ? String(localized: "이번 주 목표 달성! 🎉") : String(localized: "이번 주 \(goal - done)일 남았어요"))
                        .font(.headline)
                    if weekStreak > 0 {
                        Label("\(weekStreak)주 연속 운동 중", systemImage: "flame.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    } else {
                        Text("이번 주 첫 운동을 시작해보세요").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack {
                ForEach(weekDays, id: \.self) { day in
                    let isToday = calendar.isDateInToday(day)
                    let didWork = workoutDays.contains(day)
                    VStack(spacing: 6) {
                        Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: day) - 1])
                            .font(.caption2.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                        ZStack {
                            Circle().fill(didWork ? AnyShapeStyle(color) : AnyShapeStyle(Color.secondary.opacity(0.12)))
                            if didWork {
                                Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 30, height: 30)
                        .overlay {
                            if isToday { Circle().stroke(color, lineWidth: 2).padding(-3) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(day.formatted(.dateTime.weekday(.wide))) \(didWork ? String(localized: "운동함") : String(localized: "쉼"))"))
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
