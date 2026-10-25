import Foundation
import HealthKit

/// Runs an iPhone workout session (iOS 26+) so AirPods Pro 3 / Powerbeats heart rate
/// streams in, watches Health for Apple Watch heart rate samples, and saves the
/// finished workout to the Health app.
@MainActor
@Observable
final class HealthWorkout: NSObject {
    static let shared = HealthWorkout()

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var watchQuery: HKAnchoredObjectQuery?

    nonisolated private static let heartRateType = HKQuantityType(.heartRate)
    nonisolated private static let energyType = HKQuantityType(.activeEnergyBurned)
    nonisolated private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType(), Self.energyType],
                read: [Self.heartRateType, Self.energyType]
            )
            return true
        } catch {
            return false
        }
    }

    func start(at date: Date) async {
        guard isAvailable, session == nil else { return }
        await requestAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self
            self.session = session
            self.builder = builder
            session.startActivity(with: date)
            try await builder.beginCollection(at: date)
        } catch {
            self.session = nil
            self.builder = nil
        }
        startWatchQuery(from: date)
    }

    /// Ends the session and saves it to Health. Our own calorie estimate is attached
    /// as the workout's active energy.
    func finish(at date: Date, calories: Double) async {
        stopWatchQuery()
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.stopActivity(with: date)
        session.end()
        do {
            try await builder.endCollection(at: date)
            if calories > 0, let start = builder.startDate {
                let energy = HKQuantitySample(
                    type: Self.energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                    start: start,
                    end: date
                )
                try await builder.addSamples([energy])
            }
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
        }
    }

    func discard() {
        stopWatchQuery()
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
    }

    /// Apple Watch writes heart rate to Health; with the Watch's own workout running
    /// these arrive every few seconds, otherwise only every few minutes.
    private func startWatchQuery(from date: Date) {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil)
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, (any Error)?) -> Void = { _, samples, _, _, _ in
            guard let latest = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
            let bpm = Int(latest.quantity.doubleValue(for: Self.bpmUnit).rounded())
            let source = latest.sourceRevision.source.name
            let date = latest.endDate
            Task { @MainActor in HeartRateMonitor.shared.report(bpm, source: source, at: date) }
        }
        let query = HKAnchoredObjectQuery(
            type: Self.heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit,
            resultsHandler: handler
        )
        query.updateHandler = handler
        store.execute(query)
        watchQuery = query
    }

    private func stopWatchQuery() {
        if let watchQuery { store.stop(watchQuery) }
        watchQuery = nil
    }
}

extension HealthWorkout: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(Self.heartRateType),
              let quantity = workoutBuilder.statistics(for: Self.heartRateType)?.mostRecentQuantity() else { return }
        let bpm = Int(quantity.doubleValue(for: Self.bpmUnit).rounded())
        Task { @MainActor in HeartRateMonitor.shared.report(bpm, source: String(localized: "AirPods·Apple 기기")) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
