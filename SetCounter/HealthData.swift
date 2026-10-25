import Foundation
import HealthKit

/// A workout another app (Nike Run Club, Fitness, Strava…) saved to Health.
struct CardioWorkout: Identifiable, Hashable {
    let id: UUID
    let start: Date
    let end: Date
    let activity: HKWorkoutActivityType
    /// Meters; 0 when the activity has no distance.
    let distance: Double
    let energy: Double
    let averageHeartRate: Int
    let source: String

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Strength-type workouts from other apps still show in history, but don't count as cardio.
    var isCardio: Bool {
        ![.traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .flexibility, .cooldown, .yoga]
            .contains(activity)
    }

    var title: String {
        switch activity {
        case .running: String(localized: "러닝")
        case .walking: String(localized: "걷기")
        case .cycling: String(localized: "사이클")
        case .hiking: String(localized: "하이킹")
        case .swimming: String(localized: "수영")
        case .elliptical: String(localized: "일립티컬")
        case .rowing: String(localized: "로잉")
        case .stairClimbing, .stairs, .stepTraining: String(localized: "계단 오르기")
        case .highIntensityIntervalTraining: String(localized: "인터벌 트레이닝")
        case .jumpRope: String(localized: "줄넘기")
        case .yoga: String(localized: "요가")
        case .traditionalStrengthTraining, .functionalStrengthTraining: String(localized: "근력 운동")
        case .dance, .socialDance, .cardioDance: String(localized: "댄스")
        default: String(localized: "운동")
        }
    }

    var systemImage: String {
        switch activity {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .hiking: "figure.hiking"
        case .swimming: "figure.pool.swim"
        case .elliptical: "figure.elliptical"
        case .rowing: "figure.rower"
        case .stairClimbing, .stairs, .stepTraining: "figure.stair.stepper"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .jumpRope: "figure.jumprope"
        case .yoga: "figure.yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "figure.strengthtraining.traditional"
        case .dance, .socialDance, .cardioDance: "figure.dance"
        default: "figure.mixed.cardio"
        }
    }

    /// "5.2km · 31:20" or just the time for activities without distance.
    var summary: String {
        distance > 50
            ? "\(formatDistance(distance)) · \(formatClock(duration))"
            : formatClock(duration)
    }
}

/// A meal logged in Health. Ours carry the foods and a memo as metadata; other
/// apps' entries show with just their calories and source.
struct MealEntry: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let kcal: Double
    let type: MealType
    let foods: String
    let memo: String
    let source: String
    /// Saved by this app, so it can be deleted here.
    let isOwn: Bool

    static let typeKey = "SetCounterMealType"
    static let memoKey = "SetCounterMemo"
}

struct WeightEntry: Identifiable, Hashable {
    let date: Date
    let kg: Double
    var id: Date { date }
}

func formatDistance(_ meters: Double) -> String {
    guard meters > 0 else { return "0km" }
    return "\((meters / 1000).formatted(.number.precision(.fractionLength(meters < 10_000 ? 2 : 1))))km"
}

/// Everything read from (and written to) the Health app beyond our own strength
/// workouts. Refreshed when the app comes to the foreground and after each write.
@MainActor
@Observable
final class HealthData {
    static let shared = HealthData()

    private(set) var cardio: [CardioWorkout] = []          // newest first, past year
    private(set) var weights: [WeightEntry] = []            // oldest first, past year
    private(set) var todaySteps: Double = 0
    private(set) var todayActive: Double = 0
    private(set) var todayExerciseMinutes: Double = 0
    private(set) var todayEaten: Double = 0
    /// Per-day totals for the past few weeks, keyed by start of day, for the weekly report.
    private(set) var dailySteps: [Date: Double] = [:]
    private(set) var dailyActive: [Date: Double] = [:]
    private(set) var dailyEaten: [Date: Double] = [:]
    private(set) var dailyExercise: [Date: Double] = [:]
    /// Meals over the past four weeks, oldest first.
    private(set) var meals: [MealEntry] = []
    private(set) var needsAuthorization = false
    private(set) var lastRefresh: Date?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var refreshing = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    /// Exercise minutes come from Apple Watch; without one they stay at zero.
    var hasExerciseMinutes: Bool { dailyExercise.values.contains { $0 > 0 } }
    var latestWeight: WeightEntry? { weights.last }

    private static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceSwimming),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.bodyMass),
        HKQuantityType(.dietaryEnergyConsumed),
    ]

    private static var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.bodyMass),
            HKQuantityType(.dietaryEnergyConsumed),
        ]
        #if DEBUG
        // Only so the simulator can be filled with sample data (see seedSampleData).
        // Exercise minutes can't be written by apps; Health derives them itself.
        types.formUnion([HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)])
        #endif
        return types
    }

    /// Whether the permission sheet would still appear; the home screen offers a connect button then.
    func checkAuthorization() async {
        guard isAvailable else { return }
        let status = try? await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes)
        needsAuthorization = status == .shouldRequest
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        needsAuthorization = false
        await refresh()
    }

    func refresh(now: Date = Date()) async {
        guard isAvailable, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await checkAuthorization()
        guard !needsAuthorization else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -27, to: today) ?? today

        async let cardio = fetchCardio(since: yearAgo)
        async let weights = fetchWeights(since: yearAgo)
        async let steps = dailySums(.stepCount, unit: .count(), since: fourWeeksAgo, anchor: today)
        async let active = dailySums(.activeEnergyBurned, unit: .kilocalorie(), since: fourWeeksAgo, anchor: today)
        async let eaten = dailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), since: fourWeeksAgo, anchor: today)
        async let exercise = dailySums(.appleExerciseTime, unit: .minute(), since: fourWeeksAgo, anchor: today)
        async let meals = fetchMeals(since: fourWeeksAgo)

        self.cardio = await cardio
        self.weights = await weights
        self.meals = await meals
        dailySteps = await steps
        dailyActive = await active
        dailyEaten = await eaten
        todaySteps = dailySteps[today] ?? 0
        todayActive = dailyActive[today] ?? 0
        todayEaten = dailyEaten[today] ?? 0
        dailyExercise = await exercise
        todayExerciseMinutes = dailyExercise[today] ?? 0
        lastRefresh = now

        // Keep the calorie estimates on the latest measured weight.
        if let latest = self.weights.last {
            UserDefaults.standard.set(latest.kg, forKey: "bodyWeight")
        }
        DietSnapshot.write(health: self, now: now)
    }

    func saveWeight(_ kg: Double, at date: Date = Date()) async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date,
            end: date
        )
        try await store.save(sample)
        await refresh()
    }

    /// One sample per meal; the food names go in the standard food type field so
    /// other diet apps can show them too.
    func saveMeal(kcal: Double, type: MealType, foods: [String], memo: String, at date: Date = Date()) async throws {
        var metadata: [String: Any] = [MealEntry.typeKey: type.rawValue]
        if !foods.isEmpty { metadata[HKMetadataKeyFoodType] = foods.joined(separator: ", ") }
        let memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !memo.isEmpty { metadata[MealEntry.memoKey] = memo }
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryEnergyConsumed),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
            start: date,
            end: date,
            metadata: metadata
        )
        try await store.save(sample)
        await refresh()
    }

    func deleteMeal(_ meal: MealEntry) async throws {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryEnergyConsumed), predicate: HKQuery.predicateForObject(with: meal.id))],
            sortDescriptors: []
        )
        let samples = try await descriptor.result(for: store)
        if !samples.isEmpty { try await store.delete(samples) }
        await refresh()
    }

    func meals(on day: Date) -> [MealEntry] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    /// Cardio (and other apps' workouts) in the week containing `date`.
    func cardio(inWeekOf date: Date) -> [CardioWorkout] {
        cardio.filter { Calendar.current.isDate($0.start, equalTo: date, toGranularity: .weekOfYear) }
    }

    func cardioMinutes(inWeekOf date: Date) -> Double {
        cardio(inWeekOf: date).filter(\.isCardio).reduce(0) { $0 + $1.duration } / 60
    }

    // MARK: Queries

    private func fetchCardio(since start: Date) async -> [CardioWorkout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1000
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        // The iPhone app and its Watch app ("….watchkitapp") share this prefix.
        let ownBundle = Bundle.main.bundleIdentifier ?? "com.andykim.SetCounter"
        let distanceTypes: [HKQuantityType] = [
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
        ]
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return workouts
            // Our own strength workouts are already in the app's records.
            .filter { !($0.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundle) && $0.workoutActivityType == .traditionalStrengthTraining) }
            .map { workout in
                let distance = distanceTypes.lazy
                    .compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
                    .first ?? 0
                return CardioWorkout(
                    id: workout.uuid,
                    start: workout.startDate,
                    end: workout.endDate,
                    activity: workout.workoutActivityType,
                    distance: distance,
                    energy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0,
                    averageHeartRate: Int(workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm) ?? 0),
                    source: workout.sourceRevision.source.name
                )
            }
    }

    private func fetchMeals(since start: Date) async -> [MealEntry] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryEnergyConsumed), predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 2000
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        return samples.map { sample in
            let metadata = sample.metadata ?? [:]
            return MealEntry(
                id: sample.uuid,
                date: sample.startDate,
                kcal: sample.quantity.doubleValue(for: .kilocalorie()),
                type: (metadata[MealEntry.typeKey] as? String).flatMap(MealType.init(rawValue:)) ?? .guess(at: sample.startDate),
                foods: metadata[HKMetadataKeyFoodType] as? String ?? "",
                memo: metadata[MealEntry.memoKey] as? String ?? "",
                source: sample.sourceRevision.source.name,
                isOwn: sample.sourceRevision.source.bundleIdentifier == ownBundle
            )
        }
    }

    private func fetchWeights(since start: Date) async -> [WeightEntry] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 2000
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { WeightEntry(date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    /// Daily cumulative sums from `start` through today, keyed by start of day.
    private func dailySums(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date, anchor: Date) async -> [Date: Double] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var sums: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: Date()) { statistics, _ in
            if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                sums[Calendar.current.startOfDay(for: statistics.startDate)] = value
            }
        }
        return sums
    }

    #if DEBUG
    /// `-seedHealth` fills the simulator's Health store with a few weeks of runs,
    /// walks, steps, weights, and meals so the diet screens have something to show.
    func seedSampleData() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var samples: [HKSample] = []
        for day in 0..<28 {
            guard let date = calendar.date(byAdding: .day, value: -day, to: today) else { continue }
            let noon = date.addingTimeInterval(12 * 3600)
            samples.append(HKQuantitySample(type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: Double.random(in: 4500...11_000)),
                                            start: date.addingTimeInterval(8 * 3600), end: date.addingTimeInterval(day == 0 ? 10 * 3600 : 20 * 3600)))
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double.random(in: 250...520)),
                                            start: date.addingTimeInterval(8 * 3600), end: date.addingTimeInterval(day == 0 ? 10 * 3600 : 20 * 3600)))
            samples.append(HKQuantitySample(type: HKQuantityType(.dietaryEnergyConsumed), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: day == 0 ? 1350 : Double.random(in: 1700...2300)),
                                            start: noon, end: noon))
            if day % 2 == 0 {
                let kg = 74.6 - Double(28 - day) * 0.06 + Double.random(in: -0.2...0.2)
                samples.append(HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                                                start: date.addingTimeInterval(7 * 3600), end: date.addingTimeInterval(7 * 3600)))
            }
        }
        try? await store.save(samples)

        for (offset, activity, minutes, km) in [(1, HKWorkoutActivityType.running, 31.0, 5.2), (3, .walking, 45, 3.6), (6, .running, 28, 4.8),
                                                 (9, .cycling, 50, 15.4), (13, .running, 33, 5.5), (17, .walking, 40, 3.2)] {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let start = day.addingTimeInterval(19 * 3600)
            let end = start.addingTimeInterval(minutes * 60)
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activity
            configuration.locationType = .outdoor
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
            let distanceType = HKQuantityType(activity == .cycling ? .distanceCycling : .distanceWalkingRunning)
            do {
                try await builder.beginCollection(at: start)
                try await builder.addSamples([
                    HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: km * 1000), start: start, end: end),
                    HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: minutes * 9), start: start, end: end),
                ])
                try await builder.endCollection(at: end)
                _ = try await builder.finishWorkout()
            } catch {
                continue
            }
        }
        await refresh()
    }
    #endif
}
