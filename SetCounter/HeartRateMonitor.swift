import Foundation

/// Latest heart rate from whichever source reported last (Bluetooth strap, AirPods, Apple Watch).
@MainActor
@Observable
final class HeartRateMonitor {
    static let shared = HeartRateMonitor()

    private(set) var bpm: Int?
    private(set) var source: String?
    private(set) var updatedAt: Date?

    /// A reading older than this is treated as "no heart rate".
    static let staleAfter: TimeInterval = 30

    func currentBPM(at date: Date = Date()) -> Int? {
        guard let bpm, let updatedAt, date.timeIntervalSince(updatedAt) < Self.staleAfter else { return nil }
        return bpm
    }

    func report(_ bpm: Int, source: String, at date: Date = Date()) {
        guard (30...230).contains(bpm) else { return }
        self.bpm = bpm
        self.source = source
        updatedAt = date
    }
}

struct BodyProfile: Equatable {
    var weight: Double
    var age: Int
    var isMale: Bool

    static var saved: BodyProfile {
        let defaults = UserDefaults.standard
        return BodyProfile(
            weight: defaults.object(forKey: "bodyWeight") as? Double ?? 70,
            age: defaults.object(forKey: "age") as? Int ?? 25,
            isMale: defaults.object(forKey: "isMale") as? Bool ?? true
        )
    }

    /// kcal per minute. Uses the Keytel et al. (2005) heart-rate equation when a heart
    /// rate is known, otherwise 3.5 METs (resistance training) from the Compendium.
    func caloriesPerMinute(heartRate: Int?) -> Double {
        guard let heartRate else { return 3.5 * weight / 60 }
        let hr = Double(heartRate), age = Double(age)
        let joules = isMale
            ? -55.0969 + 0.6309 * hr + 0.1988 * weight + 0.2017 * age
            : -20.4022 + 0.4472 * hr - 0.1263 * weight + 0.074 * age
        return max(0, joules / 4.184)
    }
}
