import Foundation
import SwiftData
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

    private func suggestion(afterLifting weight: Double, reps: Int) -> RoutineSuggestion? {
        let record = WorkoutRecord(date: Date().addingTimeInterval(-86_400), exercise: "벤치프레스", sets: 3,
                                   weight: weight, reps: reps, duration: 600, routineName: part)
        container.mainContext.insert(record)
        return Coach.recommendedRoutine(for: part, records: [record], profiles: [], unit: .kg)
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
