import Foundation

/// A badge the user has earned. Kept even if the records behind it are deleted later.
struct EarnedBadge: Codable, Hashable {
    let id: String
    let earnedAt: Date
    /// Shown to the user yet (finish screen, home banner, or the collection).
    var seen: Bool
}

/// Works out badge progress from the records and Health data, and remembers what's
/// been earned. Stored as JSON in UserDefaults so backups carry it with the settings.
@MainActor
@Observable
final class BadgeCenter {
    static let shared = BadgeCenter()
    nonisolated static let storageKey = "earnedBadges"

    private(set) var earned: [String: EarnedBadge] = [:]
    private(set) var progress: [String: BadgeProgress] = [:]

    init() {
        earned = Self.load()
    }

    var unseen: [EarnedBadge] {
        earned.values.filter { !$0.seen }.sorted { $0.earnedAt > $1.earnedAt }
    }

    /// Recomputes progress and records newly reached badges, earned on the day they
    /// were actually reached. Returns the ids earned by this call.
    @discardableResult
    func update(records: [WorkoutRecord], health: HealthData, now: Date = Date()) -> [String] {
        let input = BadgeInput(
            workouts: records.map {
                BadgeInput.Workout(date: $0.date, exercise: $0.exercise, sets: $0.sets, volume: $0.volume,
                                   bestWeight: $0.bestWeight, maxReps: $0.maxReps)
            },
            cardio: health.cardio.filter(\.isCardio).map { ($0.start, $0.distance / 1000) },
            firstMeal: health.meals.first?.date,
            firstWeight: health.weights.first?.date,
            bodyWeight: BodyProfile.saved.weight,
            weeklyGoal: UserDefaults.standard.object(forKey: "weeklyGoal") as? Int ?? 4,
            now: now
        )
        progress = BadgeEngine.progress(input)
        var added: [String] = []
        for (id, item) in progress where earned[id] == nil {
            guard let date = item.achievedAt else { continue }
            earned[id] = EarnedBadge(id: id, earnedAt: date, seen: false)
            added.append(id)
        }
        if !added.isEmpty { save() }
        return added
    }

    /// Unseen badges earned at or after `date`, e.g. during the workout just finished.
    func unseen(since date: Date) -> [BadgeDefinition] {
        let ids = Set(unseen.filter { $0.earnedAt >= date.addingTimeInterval(-60) }.map(\.id))
        return BadgeDefinition.all.filter { ids.contains($0.id) }
    }

    func markSeen(_ ids: some Sequence<String>) {
        var changed = false
        for id in ids where earned[id]?.seen == false {
            earned[id]?.seen = true
            changed = true
        }
        if changed { save() }
    }

    func markAllSeen() { markSeen(Array(earned.keys)) }

    /// Picks up badges restored from a backup.
    func reload() { earned = Self.load() }

    private static func load() -> [String: EarnedBadge] {
        guard let data = UserDefaults.standard.string(forKey: storageKey)?.data(using: .utf8),
              let list = try? JSONDecoder().decode([EarnedBadge].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func save() {
        let list = earned.values.sorted { $0.earnedAt < $1.earnedAt }
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: Self.storageKey)
    }
}
