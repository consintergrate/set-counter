import SwiftUI

@MainActor
@Observable
final class WorkoutSession: Identifiable {
    enum Phase: Equatable {
        case ready
        case exercising
        case resting(until: Date)
        case alarming
        case finished
    }

    let id = UUID()
    let exercise: String
    let weight: Double
    let reps: Int
    let totalSets: Int
    let restSeconds: Int
    let alarm: RestAlarmSettings
    let routineIndex: Int
    let routineName: String

    private(set) var completedSets = 0
    private(set) var phase: Phase = .ready
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?

    private(set) var calories: Double = 0
    private(set) var heartRate: Int?
    private(set) var maxHeartRate = 0
    var averageHeartRate: Int { heartRateSamples == 0 ? 0 : heartRateTotal / heartRateSamples }

    @ObservationIgnored private let profile: BodyProfile
    @ObservationIgnored private let useHealthKit: Bool
    @ObservationIgnored private var heartRateTotal = 0
    @ObservationIgnored private var heartRateSamples = 0
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var trackingTask: Task<Void, Never>?

    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var isInBackground = false

    init(exercise: String, weight: Double, reps: Int, totalSets: Int, restSeconds: Int,
         routineIndex: Int = -1, routineName: String = "",
         alarm: RestAlarmSettings = .saved, profile: BodyProfile = .saved,
         useHealthKit: Bool = UserDefaults.standard.object(forKey: "useHealthKit") as? Bool ?? true) {
        self.routineIndex = routineIndex
        self.routineName = routineName
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.totalSets = totalSets
        self.restSeconds = restSeconds
        self.alarm = alarm
        self.profile = profile
        self.useHealthKit = useHealthKit
    }

    /// The set the user is doing now (1-based).
    var currentSet: Int { min(completedSets + 1, totalSets) }

    var duration: TimeInterval {
        guard let startedAt else { return 0 }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    func start() {
        guard phase == .ready else { return }
        let now = Date()
        startedAt = now
        phase = .exercising
        startTracking(at: now)
    }

    func completeSet() {
        guard phase == .exercising else { return }
        completedSets += 1
        if completedSets >= totalSets {
            finishedAt = Date()
            phase = .finished
            stopTracking()
            return
        }
        startRest(until: Date().addingTimeInterval(TimeInterval(restSeconds)))
    }

    func addRestTime(_ seconds: TimeInterval) {
        guard case .resting(let end) = phase else { return }
        startRest(until: max(Date(), end).addingTimeInterval(seconds))
    }

    func skipRest() {
        guard case .resting = phase else { return }
        cancelRest()
        phase = .exercising
    }

    func dismissAlarm() {
        AlarmPlayer.shared.stop()
        phase = .exercising
    }

    func end() {
        cancelRest()
        AlarmPlayer.shared.stop()
        if finishedAt == nil, startedAt != nil { finishedAt = Date() }
        stopTracking()
    }

    private func startTracking(at date: Date) {
        lastTick = date
        if useHealthKit {
            Task { await HealthWorkout.shared.start(at: date) }
        }
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTracking() {
        guard trackingTask != nil else { return }
        tick()
        trackingTask?.cancel()
        trackingTask = nil
        guard useHealthKit else { return }
        if completedSets > 0, let finishedAt {
            let calories = calories
            Task { await HealthWorkout.shared.finish(at: finishedAt, calories: calories) }
        } else {
            HealthWorkout.shared.discard()
        }
    }

    /// Integrates calories since the last tick. After a suspension the gap is covered
    /// with the current rate, which is the best guess available.
    private func tick() {
        let now = Date()
        let bpm = HeartRateMonitor.shared.currentBPM(at: now)
        heartRate = bpm
        if let bpm {
            heartRateTotal += bpm
            heartRateSamples += 1
            maxHeartRate = max(maxHeartRate, bpm)
        }
        if let lastTick {
            calories += profile.caloriesPerMinute(heartRate: bpm) * now.timeIntervalSince(lastTick) / 60
        }
        lastTick = now
    }

    func scenePhaseChanged(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            isInBackground = true
            // The app gets suspended soon, so hand the alarm to the system.
            if case .resting(let end) = phase {
                LockScreenAlarm.schedule(at: end, nextSet: currentSet)
            }
        case .active:
            isInBackground = false
            LockScreenAlarm.cancel()
            if case .resting(let end) = phase, end <= Date() {
                phase = .exercising
            }
        default:
            break
        }
    }

    private func startRest(until end: Date) {
        restTask?.cancel()
        phase = .resting(until: end)
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.restDidEnd(scheduledEnd: end)
        }
        if isInBackground {
            LockScreenAlarm.schedule(at: end, nextSet: currentSet)
        }
    }

    private func cancelRest() {
        restTask?.cancel()
        restTask = nil
        LockScreenAlarm.cancel()
    }

    private func restDidEnd(scheduledEnd: Date) {
        guard phase == .resting(until: scheduledEnd) else { return }
        // Waking up late means the app was suspended and the system alarm already rang.
        if isInBackground || Date().timeIntervalSince(scheduledEnd) > 2 {
            phase = .exercising
            return
        }
        phase = .alarming
        AlarmPlayer.shared.play(sound: alarm.sound, volume: alarm.volume, vibrate: alarm.vibrate, duration: alarm.duration) { [weak self] in
            guard let self, self.phase == .alarming else { return }
            self.phase = .exercising
        }
    }
}
