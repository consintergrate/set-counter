import Foundation
import SwiftData

@Model
final class WorkoutRecord {
    var date: Date
    var exercise: String
    /// Summary of `setEntries` (count, heaviest set's weight and reps), kept for
    /// records from before per-set logging and for quick display.
    var sets: Int
    var weight: Double
    var reps: Int
    var duration: TimeInterval
    var calories: Double = 0
    var averageHeartRate: Int = 0
    var maxHeartRate: Int = 0
    /// Position in the split routine, or -1 for records from before routines existed.
    var routineIndex: Int = -1
    var routineName: String = ""
    /// Each set's own weight and reps. Empty for records saved before per-set logging.
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.record) var setEntries: [SetEntry]? = []

    init(date: Date, exercise: String, sets: Int, weight: Double, reps: Int, duration: TimeInterval,
         calories: Double = 0, averageHeartRate: Int = 0, maxHeartRate: Int = 0,
         routineIndex: Int = -1, routineName: String = "") {
        self.routineIndex = routineIndex
        self.routineName = routineName
        self.date = date
        self.exercise = exercise
        self.sets = sets
        self.weight = weight
        self.reps = reps
        self.duration = duration
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }

    /// Sets in order. Older records without entries repeat their single weight × reps.
    var setValues: [SetValue] {
        let entries = (setEntries ?? []).sorted { $0.order < $1.order }
        if entries.isEmpty {
            return Array(repeating: SetValue(weight: weight, reps: reps), count: max(sets, 0))
        }
        return entries.map { SetValue(weight: $0.weight, reps: $0.reps) }
    }

    var volume: Double { setValues.reduce(0) { $0 + $1.volume } }
    var bestWeight: Double { setValues.map(\.weight).max() ?? 0 }
    var bestOneRepMax: Double { setValues.map(\.oneRepMax).max() ?? 0 }
    var maxReps: Int { setValues.map(\.reps).max() ?? 0 }

    /// Replaces the sets and refreshes the summary fields from them.
    func replaceSets(_ values: [SetValue], in context: ModelContext) {
        for entry in setEntries ?? [] { context.delete(entry) }
        let entries = values.enumerated().map { SetEntry(order: $0.offset, weight: $0.element.weight, reps: $0.element.reps) }
        entries.forEach(context.insert)
        setEntries = entries
        sets = values.count
        let top = values.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
        weight = top?.weight ?? 0
        reps = top?.reps ?? 0
    }
}

@Model
final class SetEntry {
    var order: Int
    var weight: Double
    var reps: Int
    var record: WorkoutRecord?

    init(order: Int, weight: Double, reps: Int) {
        self.order = order
        self.weight = weight
        self.reps = reps
    }
}

/// The body part an exercise trains, set by the user or guessed from its name.
@Model
final class ExerciseProfile {
    @Attribute(.unique) var name: String
    var muscleRaw: String

    init(name: String, muscle: Muscle) {
        self.name = name
        self.muscleRaw = muscle.rawValue
    }

    var muscle: Muscle { Muscle(rawValue: muscleRaw) ?? .other }
}

struct SetValue: Hashable, Codable {
    var weight: Double
    var reps: Int

    var volume: Double { weight * Double(reps) }
    var oneRepMax: Double { estimatedOneRepMax(weight: weight, reps: reps) }
}

/// Epley: weight × (1 + reps / 30). A single rep is the max itself.
func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
    guard weight > 0, reps > 0 else { return 0 }
    return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
}

enum Muscle: String, CaseIterable, Identifiable, Codable {
    case chest, back, shoulders, biceps, triceps, legs, core, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: String(localized: "가슴")
        case .back: String(localized: "등")
        case .shoulders: String(localized: "어깨")
        case .biceps: String(localized: "이두")
        case .triceps: String(localized: "삼두")
        case .legs: String(localized: "하체")
        case .core: String(localized: "복근")
        case .other: String(localized: "기타")
        }
    }

    /// Muscles the weekly balance check covers.
    static let tracked: [Muscle] = [.chest, .back, .shoulders, .biceps, .triceps, .legs, .core]

    /// Keyword guess, checked in an order that resolves overlaps
    /// ("레그 컬" is legs, "숄더프레스" is shoulders, plain "프레스" is chest).
    static func guess(for name: String) -> Muscle {
        let text = name.lowercased().replacingOccurrences(of: " ", with: "")
        let table: [(Muscle, [String])] = [
            (.legs, ["스쿼트", "레그", "런지", "카프", "힙", "데드리프트", "squat", "leg", "lunge", "calf", "hip", "deadlift"]),
            (.shoulders, ["숄더", "오버헤드", "밀리터리", "레이즈", "shoulder", "overhead", "military", "raise", "ohp"]),
            (.triceps, ["푸시다운", "푸쉬다운", "딥스", "트라이셉", "삼두", "킥백", "익스텐션", "pushdown", "dip", "tricep", "kickback", "extension", "skull"]),
            (.biceps, ["컬", "이두", "curl", "bicep"]),
            (.back, ["로우", "풀업", "풀다운", "랫", "턱걸이", "백", "row", "pullup", "pulldown", "lat", "chin", "back"]),
            (.chest, ["벤치", "체스트", "플라이", "푸시업", "푸쉬업", "가슴", "프레스", "bench", "chest", "fly", "pushup", "press"]),
            (.core, ["크런치", "플랭크", "복근", "싯업", "윗몸", "crunch", "plank", "abs", "situp"]),
        ]
        return table.first { _, keywords in keywords.contains { text.contains($0) } }?.0 ?? .other
    }

    static func lookup(_ name: String, in profiles: [ExerciseProfile]) -> Muscle {
        profiles.first { $0.name == name }?.muscle ?? guess(for: name)
    }
}

/// Best numbers per exercise, used by the PR board and in-workout PR alerts.
struct PersonalBest: Equatable {
    var weight: Double = 0
    var weightDate: Date?
    var oneRepMax: Double = 0
    var oneRepMaxDate: Date?
    var reps: Int = 0
    var repsDate: Date?

    var latestDate: Date? { [weightDate, oneRepMaxDate, repsDate].compactMap { $0 }.max() }

    /// When the headline record was set: weight or 1RM for weighted lifts, reps for bodyweight.
    var headlineDate: Date? {
        weight > 0 ? [weightDate, oneRepMaxDate].compactMap { $0 }.max() : repsDate
    }

    static func of(_ exercise: String, in records: [WorkoutRecord]) -> PersonalBest? {
        let matching = records.filter { $0.exercise == exercise }
        guard !matching.isEmpty else { return nil }
        var best = PersonalBest()
        for record in matching.sorted(by: { $0.date < $1.date }) {
            for set in record.setValues {
                if set.weight > best.weight { best.weight = set.weight; best.weightDate = record.date }
                if set.oneRepMax > best.oneRepMax { best.oneRepMax = set.oneRepMax; best.oneRepMaxDate = record.date }
                if set.reps > best.reps { best.reps = set.reps; best.repsDate = record.date }
            }
        }
        return best
    }
}

/// "65kg × 10회 × 5세트" when every set matches, "65kg × 10/10/8회" when only reps
/// change, otherwise "5세트 · 60–70kg".
func setsSummary(_ values: [SetValue], unit: WeightUnit = .current) -> String {
    guard let first = values.first else { return String(localized: "\(0)세트") }
    if values.allSatisfy({ $0 == first }) {
        return String(localized: "\(formatWeight(first.weight, unit: unit)) × \(first.reps)회 × \(values.count)세트")
    }
    if values.allSatisfy({ $0.weight == first.weight }) {
        let reps = values.map { String($0.reps) }.joined(separator: "/")
        return String(localized: "\(formatWeight(first.weight, unit: unit)) × \(reps)회")
    }
    let weights = values.map(\.weight)
    let low = weights.min() ?? 0, high = weights.max() ?? 0
    let range = low == high ? formatWeight(high, unit: unit) : "\(formatWeight(low, unit: unit))–\(formatWeight(high, unit: unit))"
    return String(localized: "\(values.count)세트 · \(range)")
}

/// Formats a weight stored in kg in the chosen display unit; 0 means bodyweight.
func formatWeight(_ kg: Double, unit: WeightUnit = .current) -> String {
    kg == 0 ? String(localized: "맨몸") : formatMass(kg, unit: unit)
}

/// Formats a mass (e.g. total volume) stored in kg in the chosen display unit.
func formatMass(_ kg: Double, unit: WeightUnit = .current) -> String {
    let value = unit.fromKg(kg)
    let digits = value >= 1000 ? 0...0 : 0...1
    return "\(value.formatted(.number.precision(.fractionLength(digits))))\(unit.symbol)"
}

func formatClock(_ interval: TimeInterval) -> String {
    let seconds = Int(interval)
    if seconds >= 3600 {
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
