import HealthKit
import WatchKit

/// Runs the strength workout on the Watch while the iPhone counts sets: heart rate
/// goes to the iPhone over a mirrored session, the set count and rest come back,
/// and the wrist gets a tap when rest is over. The Watch saves the workout to Health.
@MainActor
@Observable
final class WatchWorkout: NSObject {
    static let shared = WatchWorkout()

    private(set) var isRunning = false
    private(set) var heartRate: Int?
    private(set) var startDate: Date?
    private(set) var exercise = ""
    private(set) var setsDone = 0
    private(set) var setsTotal = 0
    private(set) var restEnd: Date?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var restTap: Task<Void, Never>?

    nonisolated private static let heartRateType = HKQuantityType(.heartRate)
    nonisolated private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    func requestAuthorization() async {
        try? await store.requestAuthorization(
            toShare: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)],
            read: [Self.heartRateType, HKQuantityType(.activeEnergyBurned)]
        )
    }

    func start(_ configuration: HKWorkoutConfiguration) async {
        guard session == nil else { return }
        await requestAuthorization()
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            try await session.startMirroringToCompanionDevice()
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            startDate = now
            isRunning = true
        } catch {
            session?.end()
            reset()
        }
    }

    /// Saves the workout to Health, or throws it away when no sets were done.
    func end(save: Bool) async {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        let now = Date()
        session.stopActivity(with: now)
        session.end()
        if save {
            do {
                try await builder.endCollection(at: now)
                _ = try await builder.finishWorkout()
            } catch {
                builder.discardWorkout()
            }
        } else {
            builder.discardWorkout()
        }
        reset()
    }

    private func reset() {
        session = nil
        builder = nil
        isRunning = false
        heartRate = nil
        startDate = nil
        exercise = ""
        setsDone = 0
        setsTotal = 0
        restEnd = nil
        restTap?.cancel()
        restTap = nil
    }

    private func send(_ message: WatchMessage) {
        guard let session, let data = try? JSONEncoder().encode(message) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    fileprivate func receive(_ message: WatchMessage) {
        switch message.command {
        case .end:
            Task { await end(save: true) }
        case .discard:
            Task { await end(save: false) }
        case nil:
            exercise = message.exercise ?? exercise
            setsDone = message.setsDone ?? setsDone
            setsTotal = message.setsTotal ?? setsTotal
            if message.restEnd != restEnd {
                restEnd = message.restEnd
                scheduleRestTap()
            }
        }
    }

    /// The workout session keeps the app running in the background, so a plain
    /// timer is enough to tap the wrist when rest is over.
    private func scheduleRestTap() {
        restTap?.cancel()
        guard let restEnd, restEnd > Date() else { return }
        restTap = Task {
            try? await Task.sleep(for: .seconds(restEnd.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.notification)
        }
    }

    fileprivate func heartRateArrived(_ bpm: Int) {
        heartRate = bpm
        send(WatchMessage(bpm: bpm))
    }

    fileprivate func sessionStopped(_ stopped: HKWorkoutSession) {
        // Ended by the system or another app; save what was collected.
        guard stopped === session else { return }
        Task { await end(save: true) }
    }
}

extension WatchWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in self.sessionStopped(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in self.sessionStopped(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap { try? JSONDecoder().decode(WatchMessage.self, from: $0) }
        Task { @MainActor in messages.forEach(self.receive) }
    }
}

extension WatchWorkout: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(Self.heartRateType),
              let quantity = workoutBuilder.statistics(for: Self.heartRateType)?.mostRecentQuantity() else { return }
        let bpm = Int(quantity.doubleValue(for: Self.bpmUnit).rounded())
        Task { @MainActor in self.heartRateArrived(bpm) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
