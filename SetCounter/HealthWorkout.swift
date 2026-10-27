import Foundation
import HealthKit

/// Live heart rate during a workout, from the best source available:
/// - Apple Watch: the Watch app runs the workout and streams heart rate over a
///   mirrored session every few seconds, and saves the workout to Health itself.
/// - Otherwise an iPhone workout session (iOS 26+), which streams AirPods Pro 3 /
///   Powerbeats heart rate and saves the finished workout to Health.
/// Health is also watched for heart rate samples as a backup.
@MainActor
@Observable
final class HealthWorkout: NSObject {
    static let shared = HealthWorkout()
    nonisolated static let useWatchKey = "useAppleWatch"

    /// The Watch app is running this workout and sending heart rate.
    private(set) var isWatchConnected = false

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var mirrored: HKWorkoutSession?
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?
    @ObservationIgnored private var watchQuery: HKAnchoredObjectQuery?
    @ObservationIgnored private var lastSentState: WatchMessage?
    /// A workout is running on the iPhone (between start and finish/discard).
    @ObservationIgnored private var workoutActive = false
    /// Finish or discard that came before the Watch's session did; sent when it arrives.
    @ObservationIgnored private var lateCommand: WatchMessage.Command?

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

    /// Called at launch: the system can start the app in the background to hand
    /// over the session the Watch app just started.
    func setUpMirroring() {
        store.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in HealthWorkout.shared.attach(mirrored: session) }
        }
    }

    func start(at date: Date) async {
        guard isAvailable, session == nil, mirrored == nil else { return }
        workoutActive = true
        lateCommand = nil
        await requestAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        startWatchQuery(from: date)

        // Ask the Watch app (a Pro feature) to run the workout. If there's no Watch (or no
        // app on it), or its session never shows up, use the iPhone's own session instead.
        if ProStore.shared.isPro, UserDefaults.standard.object(forKey: Self.useWatchKey) as? Bool ?? true {
            let launched = await withCheckedContinuation { continuation in
                store.startWatchApp(with: configuration) { success, _ in continuation.resume(returning: success) }
            }
            if launched {
                fallbackTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled, let self, self.mirrored == nil else { return }
                    await self.startPhoneSession(configuration, at: date)
                }
                return
            }
        }
        await startPhoneSession(configuration, at: date)
    }

    private func startPhoneSession(_ configuration: HKWorkoutConfiguration, at date: Date) async {
        guard session == nil, mirrored == nil else { return }
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
    }

    private func attach(mirrored session: HKWorkoutSession) {
        fallbackTask?.cancel()
        // The workout already ended on the iPhone (finished within the wait, or the
        // app was relaunched without one): end the Watch's session right away so it
        // doesn't keep running on the wrist.
        guard workoutActive else {
            send(WatchMessage(command: lateCommand ?? .end), to: session)
            lateCommand = nil
            return
        }
        // The Watch took a while and the iPhone session already started: keep only one.
        if let phoneSession = self.session {
            phoneSession.end()
            builder?.discardWorkout()
            self.session = nil
            builder = nil
        }
        mirrored = session
        session.delegate = self
        isWatchConnected = true
        lastSentState = nil
    }

    /// Keeps the Watch screen showing the sets and rest, and lets it tap the wrist
    /// when rest ends. Called every second by the workout; only changes are sent.
    func syncWatch(exercise: String, setsDone: Int, setsTotal: Int, restEnd: Date?) {
        guard let mirrored else { return }
        let state = WatchMessage(exercise: exercise, setsDone: setsDone, setsTotal: setsTotal, restEnd: restEnd)
        guard state != lastSentState else { return }
        lastSentState = state
        send(state, to: mirrored)
    }

    private func send(_ message: WatchMessage, to session: HKWorkoutSession) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    /// The Watch saves (or throws away) its own workout; the iPhone just tells it to.
    private func endMirrored(_ command: WatchMessage.Command) -> Bool {
        fallbackTask?.cancel()
        workoutActive = false
        guard let mirrored else {
            // Still waiting for the Watch: remember what to tell it when it connects.
            lateCommand = command
            return false
        }
        send(WatchMessage(command: command), to: mirrored)
        self.mirrored = nil
        isWatchConnected = false
        return true
    }

    /// Ends the session and saves it to Health. Our own calorie estimate is attached
    /// as the workout's active energy.
    func finish(at date: Date, calories: Double) async {
        stopWatchQuery()
        if endMirrored(.end) { return }
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
        _ = endMirrored(.discard)
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
    }

    /// Backup for Watches without the app: heart rate samples synced into Health.
    /// They reach the iPhone in batches, often a minute late, so a reading counts
    /// from when it arrives as long as it was measured in the last two minutes.
    private func startWatchQuery(from date: Date) {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil)
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, (any Error)?) -> Void = { _, samples, _, _, _ in
            guard let latest = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }),
                  latest.endDate > Date().addingTimeInterval(-120) else { return }
            let bpm = Int(latest.quantity.doubleValue(for: Self.bpmUnit).rounded())
            let source = latest.sourceRevision.source.name
            Task { @MainActor in
                // A live Watch stream is fresher; don't let a late batch overwrite it.
                guard !HealthWorkout.shared.isWatchConnected else { return }
                HeartRateMonitor.shared.report(bpm, source: source)
            }
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

extension HealthWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.mirroredDidEnd(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in self.mirroredDidEnd(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let bpm = data.compactMap { try? JSONDecoder().decode(WatchMessage.self, from: $0) }.last(where: { $0.bpm != nil })?.bpm
        guard let bpm else { return }
        Task { @MainActor in HeartRateMonitor.shared.report(bpm, source: "Apple Watch") }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor in self.mirroredDidEnd(workoutSession) }
    }

    /// Ended from the Watch (or the connection dropped): the backup sources take over.
    private func mirroredDidEnd(_ workoutSession: HKWorkoutSession) {
        guard mirrored === workoutSession else { return }
        mirrored = nil
        isWatchConnected = false
    }
}
