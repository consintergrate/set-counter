import Foundation
import SwiftData

@Model
final class WorkoutRecord {
    var date: Date
    var exercise: String
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

    var volume: Double { weight * Double(reps * sets) }
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
