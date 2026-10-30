import Foundation
import StoreKitTest
import SwiftData
import SwiftUI
import Testing
@testable import SetCounter

@Suite("Calories")
struct CalorieTests {
    private let profile = BodyProfile(weight: 73, age: 25, isMale: true)

    private func goals(weeklyLoss: Double) -> Goals {
        Goals(heightCm: 172, goalWeight: 68, weeklyLoss: weeklyLoss, steps: 8000,
              activeCalories: 400, exerciseMinutes: 30, cardioWeeklyMinutes: 150)
    }

    @Test func basalMetabolicRateUsesMifflinStJeor() {
        // 10 × 73 + 6.25 × 172 − 5 × 25 + 5
        #expect(Goals.basalMetabolicRate(weight: 73, heightCm: 172, age: 25, isMale: true) == 1685)
        #expect(Goals.basalMetabolicRate(weight: 60, heightCm: 160, age: 30, isMale: false) == 1289)
    }

    @Test func maintainingTargetsTheBMR() {
        let breakdown = goals(weeklyLoss: 0).intakeBreakdown(profile: profile)
        #expect(breakdown.target == 1685)
        #expect(!breakdown.floorApplied)
    }

    @Test func weeklyLossTakesItsDeficit() {
        // BMR 1,880 (90 kg, 180 cm, 30, male); 0.25 kg a week is 7,700 / 4 / 7 = 275 a day.
        var tall = goals(weeklyLoss: 0.25)
        tall.heightCm = 180
        let breakdown = tall.intakeBreakdown(profile: BodyProfile(weight: 90, age: 30, isMale: true))
        #expect(breakdown.deficit == 275)
        #expect(breakdown.target == 1605)
        #expect(!breakdown.floorApplied)
    }

    @Test func targetNeverGoesBelowTheSafeFloor() {
        let man = goals(weeklyLoss: 0.75).intakeBreakdown(profile: profile)
        #expect(man.target == 1500)
        #expect(man.floorApplied)
        let woman = goals(weeklyLoss: 0.75).intakeBreakdown(profile: BodyProfile(weight: 55, age: 30, isMale: false))
        #expect(woman.target == 1200)
    }

    @Test func activityIsAddedOnceToWhatCanBeEaten() {
        let budget = CalorieBudget(target: 1500, eaten: 1770, exercise: 356)
        #expect(budget.remaining == 86)
    }

    @Test func runningMinutesRoundUp() {
        // 9.8 METs at 70 kg burns 11.43 kcal a minute.
        #expect(runningMinutes(toBurn: 300, weight: 70) == 27)
        #expect(runningMinutes(toBurn: 0, weight: 70) == 0)
    }

    @Test func epleyOneRepMax() {
        #expect(abs(estimatedOneRepMax(weight: 100, reps: 10) - 133.33) < 0.01)
        #expect(estimatedOneRepMax(weight: 100, reps: 1) == 100)
        #expect(estimatedOneRepMax(weight: 0, reps: 10) == 0)
    }
}

@Suite("Exercises")
struct ExerciseTests {
    @Test(arguments: [
        ("가슴·삼두", [Muscle.chest, .triceps]),
        ("등·이두", [.back, .biceps]),
        ("Upper Body", [.chest, .back, .shoulders]),
        ("전신", [.chest, .back, .legs, .shoulders]),
        ("팔", [.biceps, .triceps]),
        ("복근·유산소", [.core]),
    ])
    func routinePartNamesMapToMuscles(part: String, muscles: [Muscle]) {
        #expect(Coach.muscles(in: part) == muscles)
    }

    @Test func keywordGuessResolvesOverlaps() {
        #expect(Muscle.guess(for: "레그 컬") == .legs)
        #expect(Muscle.guess(for: "숄더프레스") == .shoulders)
        #expect(Muscle.guess(for: "벤치프레스") == .chest)
        #expect(Muscle.guess(for: "Push-up") == .chest)
    }

    @Test func libraryMatchesDifferentSpacingAndCase() throws {
        // Names are localized, so take them from the list rather than hard-coding one language.
        let spaced = try #require(ExerciseLibrary.all.first { $0.name.contains(" ") })
        let squashed = spaced.name.replacingOccurrences(of: " ", with: "").uppercased()
        #expect(ExerciseLibrary.find(squashed) == spaced)
        #expect(ExerciseLibrary.find("없는 운동 이름") == nil)
    }

    @Test func starterNamesGuessTheirOwnMuscle() {
        // Records keep only the name; an exercise saved before the list existed (or
        // typed by hand) must still land on the same muscle from its name alone.
        for exercise in ExerciseLibrary.all where exercise.starter {
            #expect(Muscle.guess(for: exercise.name) == exercise.muscle, "\(exercise.name)")
        }
    }
}

@Suite("Suggested routine")
@MainActor
struct ProgressionTests {
    private let container = try! ModelContainer(for: WorkoutRecord.self, SetEntry.self, ExerciseProfile.self,
                                                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    /// A part name no saved routine plan uses.
    private let part = "테스트 가슴"

    private func suggestion(afterLifting weight: Double, reps: Int, progresses: Bool = true) -> RoutineSuggestion? {
        let record = WorkoutRecord(date: Date().addingTimeInterval(-86_400), exercise: "벤치프레스", sets: 3,
                                   weight: weight, reps: reps, duration: 600, routineName: part)
        container.mainContext.insert(record)
        return Coach.recommendedRoutine(for: part, records: [record], profiles: [], unit: .kg, progresses: progresses)
            .first { $0.exercise == "벤치프레스" }
    }

    @Test func twelveRepsAddsWeight() throws {
        let next = try #require(suggestion(afterLifting: 70, reps: 12))
        #expect(next.weight == 72.5)
        #expect(next.reps == 8)
    }

    @Test func eightRepsAddsARep() throws {
        let next = try #require(suggestion(afterLifting: 70, reps: 10))
        #expect(next.weight == 70)
        #expect(next.reps == 11)
    }

    @Test func fewerRepsRepeats() throws {
        let next = try #require(suggestion(afterLifting: 70, reps: 6))
        #expect(next.weight == 70)
        #expect(next.reps == 6)
    }

    @Test func withoutProTheNumbersStayAtLastTime() throws {
        let next = try #require(suggestion(afterLifting: 70, reps: 12, progresses: false))
        #expect(next.weight == 70)
        #expect(next.reps == 12)
    }

    @Test func emptyHistoryFallsBackToStarters() {
        let suggestions = Coach.recommendedRoutine(for: part, records: [], profiles: [], unit: .kg)
        #expect(suggestions.count == 4)
        #expect(suggestions.allSatisfy { $0.isNew && $0.muscle == .chest })
    }
}

@Suite("Widget and Watch data")
struct SharedDataTests {
    @Test func dietSnapshotResetsOnANewDay() throws {
        let morning = try #require(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()))
        let snapshot = DietSnapshot(date: morning, target: 1500, eaten: 800, active: 200,
                                    weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: morning)!.start,
                                    cardioMinutes: 60, cardioGoal: 150, accent: "blue")
        #expect(snapshot.remaining(at: morning) == 900)
        let tomorrow = morning.addingTimeInterval(86_400)
        #expect(snapshot.remaining(at: tomorrow) == 1500)
        #expect(snapshot.cardioMinutes(at: morning.addingTimeInterval(8 * 86_400)) == 0)
    }

    @Test func watchMessageRoundTrips() throws {
        let message = WatchMessage(exercise: "벤치프레스", setsDone: 2, setsTotal: 5, restEnd: Date(timeIntervalSince1970: 1_000))
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: JSONEncoder().encode(message))
        #expect(decoded == message)
        let heartRate = try JSONDecoder().decode(WatchMessage.self, from: JSONEncoder().encode(WatchMessage(bpm: 128)))
        #expect(heartRate.bpm == 128)
        #expect(heartRate.command == nil)
    }
}

@Suite("Meals")
struct MealTests {
    @Test(arguments: [(7, MealType.breakfast), (12, .lunch), (19, .dinner), (23, .snack), (3, .snack)])
    func mealTypeFollowsTheClock(hour: Int, type: MealType) throws {
        let date = try #require(Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: Date()))
        #expect(MealType.guess(at: date) == type)
    }

    @Test func amountsScaleCaloriesAndShowInTheLog() {
        let rice = FoodItem(name: "공깃밥 1공기", kcal: 300)
        #expect(FoodLogSheet.Line(food: rice, amount: 1).label == "공깃밥 1공기")
        let double = FoodLogSheet.Line(food: rice, amount: 1.5)
        #expect(double.kcal == 450)
        #expect(double.label.hasSuffix("×1.5"))
    }

    @Test func builtInFoodsAreUniqueAndSane() {
        let all = FoodCatalog.all
        #expect(all.count >= 70)
        #expect(Set(all.map(\.name)).count == all.count)
        #expect(all.allSatisfy { (0...1500).contains($0.kcal) })
    }
}

@Suite("CSV")
struct CSVTests {
    @Test func formulasAreDefusedOnExport() {
        #expect(CSVExporter.escape("=HYPERLINK(\"x\")").hasPrefix("\"'="))
        #expect(CSVExporter.escape("+1") == "'+1")
        #expect(CSVExporter.escape("벤치프레스") == "벤치프레스")
        #expect(CSVExporter.escape("a,b") == "\"a,b\"")
    }

    @Test func importRestoresTheOriginalName() throws {
        let csv = "date,exercise,weight_kg,reps,sets\n2026-10-25T10:00:00+09:00,'=SUM(A1),60,10,3\n"
        let records = try CSVImporter.records(from: Data(csv.utf8))
        #expect(records.first?.exercise == "=SUM(A1)")
    }
}

@Suite("Exercise minutes")
struct ExerciseMinuteTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func interval(_ fromMinute: Double, _ toMinute: Double) -> DateInterval {
        DateInterval(start: start.addingTimeInterval(fromMinute * 60), end: start.addingTimeInterval(toMinute * 60))
    }

    @Test func separateWorkoutsAddUp() {
        #expect(coveredDuration([interval(0, 20), interval(60, 90)]) == 50 * 60)
    }

    @Test func overlappingWorkoutsCountOnce() {
        // A Set Counter session inside an Apple Watch workout is one workout.
        #expect(coveredDuration([interval(0, 45), interval(10, 30)]) == 45 * 60)
        #expect(coveredDuration([interval(30, 60), interval(0, 40)]) == 60 * 60)
    }

    @Test func nothingIsZero() {
        #expect(coveredDuration([]) == 0)
    }
}

@Suite("Badges")
struct BadgeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        return calendar
    }()

    /// Noon on 2026-09-06 (a Sunday) plus `day` days.
    private func date(_ day: Int) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        return calendar.date(byAdding: .day, value: day, to: start)!
    }

    private func workout(_ day: Int, _ exercise: String = "벤치프레스", weight: Double = 60, reps: Int = 10, sets: Int = 5) -> BadgeInput.Workout {
        BadgeInput.Workout(date: date(day), exercise: exercise, sets: sets, volume: weight * Double(reps * sets),
                           bestWeight: weight, maxReps: reps)
    }

    private func progress(_ input: BadgeInput) -> [String: BadgeProgress] {
        BadgeEngine.progress(input, calendar: calendar)
    }

    @Test func everyBadgeHasAUniqueId() {
        let ids = BadgeDefinition.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count >= 30)
    }

    @Test func workoutDaysCountDaysNotRecords() {
        // Two exercises on each of 10 days: 10 days, earned on the 10th day.
        let workouts = (0..<10).flatMap { [workout($0), workout($0, "스쿼트")] }
        let result = progress(BadgeInput(workouts: workouts, now: date(20)))
        #expect(result["workout-days-10"]?.value == 10)
        #expect(result["workout-days-10"]?.achievedAt == date(9))
        #expect(result["workout-days-30"]?.achievedAt == nil)
        #expect(result["first-workout"]?.achievedAt == date(0))
    }

    @Test func setsAndVolumeAddUp() {
        let workouts = (0..<20).map { workout($0, sets: 5) }   // 100 sets, 60 × 10 × 5 = 3,000 kg each
        let result = progress(BadgeInput(workouts: workouts, now: date(30)))
        #expect(result["sets-100"]?.achievedAt == date(19))
        #expect(result["volume-10000"]?.achievedAt == date(3))
    }

    @Test func recordsCountOnlyBeatingEarlierSessions() {
        let workouts = [workout(0, weight: 60), workout(2, weight: 62.5), workout(4, weight: 62.5), workout(6, weight: 65)]
        let result = progress(BadgeInput(workouts: workouts, now: date(10)))
        #expect(result["records-10"]?.value == 2)
        #expect(result["first-record"]?.achievedAt == date(2))
    }

    @Test func dayStreakTakesTheBestRun() {
        let days = [0, 1, 2, 5, 6, 7, 8, 9, 10, 11]   // 3 in a row, then 7 in a row
        let result = progress(BadgeInput(workouts: days.map { workout($0) }, now: date(15)))
        #expect(result["day-streak-3"]?.achievedAt == date(2))
        #expect(result["day-streak-7"]?.achievedAt == date(11))
    }

    @Test func weekStreakNeedsTheWeeklyGoalEachWeek() {
        // Weeks start on Sunday (day 0, 7, 14…). Two days a week for 4 weeks, goal 2.
        let days = [0, 2, 7, 9, 14, 16, 21, 23]
        let result = progress(BadgeInput(workouts: days.map { workout($0) }, weeklyGoal: 2, now: date(27)))
        #expect(result["week-streak-2"]?.achievedAt == date(9))
        #expect(result["week-streak-4"]?.achievedAt == date(23))
    }

    @Test func theWeekInProgressDoesNotBreakAStreak() {
        let days = [0, 2, 7, 9]
        // Day 15 is in the third week, with nothing logged yet: the streak is still 2.
        let result = progress(BadgeInput(workouts: days.map { workout($0) }, weeklyGoal: 2, now: date(15)))
        #expect(result["week-streak-2"]?.value == 2)
    }

    @Test func liftsCompareWithBodyWeight() {
        let workouts = [workout(0, "벤치프레스", weight: 60), workout(3, "인클라인 벤치프레스", weight: 90), workout(5, "벤치프레스", weight: 80)]
        let result = progress(BadgeInput(workouts: workouts, bodyWeight: 80, now: date(10)))
        // 60/80 = 0.75 on day 0, 80/80 = 1.0 on day 5; the incline set doesn't count.
        #expect(result["bench-0.75"]?.achievedAt == date(0))
        #expect(result["bench-1"]?.achievedAt == date(5))
        #expect(result["bench-1.25"]?.achievedAt == nil)
    }

    @Test(arguments: [
        ("벤치프레스", BigLift.bench, true), ("바벨 벤치 프레스", .bench, true), ("인클라인 벤치프레스", .bench, false),
        ("덤벨 벤치프레스", .bench, false), ("스쿼트", .squat, true), ("불가리안 스플릿 스쿼트", .squat, false),
        ("데드리프트", .deadlift, true), ("루마니안 데드리프트", .deadlift, false), ("Deadlift", .deadlift, true),
    ])
    func bigLiftsSkipVariations(name: String, lift: BigLift, matches: Bool) {
        #expect(lift.matches(name) == matches)
    }

    @Test func cardioDistanceAddsUp() {
        let cardio = [(date(0), 5.2), (date(3), 4.8), (date(6), 3.0)]
        let result = progress(BadgeInput(cardio: cardio, now: date(10)))
        #expect(result["first-cardio"]?.achievedAt == date(0))
        #expect(result["cardio-km-10"]?.achievedAt == date(3))
    }
}

@Suite("Pro", .serialized)
@MainActor
struct ProTests {
    private static let configuration = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Config/SetCounter.storekit")

    @Test func yearlyPlanSavesAgainstTwelveMonths() {
        #expect(ProPlan.yearlySavings(yearly: 22000, monthly: 2900) == 37)
        #expect(ProPlan.yearlySavings(yearly: 40000, monthly: 2900) == nil)
    }

    @Test func lifetimeWinsAndLapsedPurchasesDoNotCount() {
        let now = Date()
        let lapsed = ProStore.Entitlement(productID: ProPlan.monthly.productID, expiration: now.addingTimeInterval(-60))
        #expect(ProStore.bestPlan([lapsed], now: now) == nil)

        let yearly = ProStore.Entitlement(productID: ProPlan.yearly.productID, expiration: now.addingTimeInterval(86_400))
        let lifetime = ProStore.Entitlement(productID: ProPlan.lifetime.productID)
        #expect(ProStore.bestPlan([yearly, lifetime], now: now)?.plan == .lifetime)

        let refunded = ProStore.Entitlement(productID: ProPlan.lifetime.productID, revoked: true)
        #expect(ProStore.bestPlan([refunded, yearly], now: now)?.plan == .yearly)
        #expect(ProStore.bestPlan([ProStore.Entitlement(productID: "com.example.other")], now: now) == nil)
    }

    /// Runs the real StoreKit calls against the local configuration file.
    @Test func buyingAPlanUnlocksProUntilItIsGone() async throws {
        let session = try SKTestSession(contentsOf: Self.configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let defaults = try #require(UserDefaults(suiteName: "ProTests"))
        defaults.removePersistentDomain(forName: "ProTests")
        let store = ProStore(defaults: defaults, updatesWidgets: false)
        await store.loadProducts()
        #expect(Set(store.products.keys) == Set(ProPlan.allCases))
        #expect(store.amount(.yearly) == 22000)
        #expect(ProPlan.yearlySavings(yearly: store.amount(.yearly) ?? 0, monthly: store.amount(.monthly) ?? 0) == 37)
        #expect(store.trialEligible)
        await store.refreshEntitlements()
        #expect(!store.isPro)

        // A purchase opens Pro at once, before StoreKit lists it as an entitlement.
        let bought = try await session.buyProduct(identifier: ProPlan.yearly.productID)
        await store.refreshEntitlements(adding: bought)
        #expect(store.isPro)
        #expect(store.activePlan == .yearly)
        #expect(store.renewalDate != nil)
        // The answer is remembered for the next launch.
        #expect(ProStore(defaults: defaults, updatesWidgets: false).isPro)

        // StoreKit's own list catches up; once the purchase is gone, so is Pro.
        try await waitUntil { await store.refreshEntitlements(); return store.activePlan == .yearly }
        session.clearTransactions()
        try await waitUntil { await store.refreshEntitlements(); return !store.isPro }
        #expect(store.activePlan == nil)
    }

    /// StoreKit's test store updates in the background; give it up to three seconds.
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<30 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("StoreKit didn't catch up in time")
    }
}

@Suite("Readable colors")
struct ReadableColorTests {
    private func contrastWithWhite(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ value: CGFloat) -> CGFloat { value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return 1.05 / (luminance + 0.05)
    }

    @Test(arguments: [Color.orange, .green, .teal, .red, .pink, .cyan, .mint, .yellow])
    func smallTextReachesFourAndAHalfToOneInLightMode(color: Color) {
        let light = UIColor(color.readable).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(contrastWithWhite(light) >= 4.5)
    }

    @Test func darkModeKeepsTheSystemColor() {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        let readable = UIColor(Color.orange.readable).resolvedColor(with: traits)
        #expect(readable == UIColor.systemOrange.resolvedColor(with: traits))
    }

    @Test func proButtonsKeepWhiteTextReadable() {
        for color in ProStyle.colors {
            #expect(contrastWithWhite(UIColor(color)) >= 4.5)
        }
    }
}
