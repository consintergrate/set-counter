import SwiftUI

/// Diet and activity targets, stored in UserDefaults like the other settings.
struct Goals: Equatable {
    static let heightKey = "heightCm"
    static let goalWeightKey = "goalWeight"
    static let weeklyLossKey = "weeklyLossKg"
    static let stepKey = "stepGoal"
    static let activeKey = "activeGoal"
    static let exerciseKey = "exerciseGoal"
    static let cardioKey = "cardioWeeklyMinutes"

    var heightCm: Double
    var goalWeight: Double
    /// Planned loss per week in kg; 0 means maintain.
    var weeklyLoss: Double
    var steps: Int
    var activeCalories: Int
    var exerciseMinutes: Int
    var cardioWeeklyMinutes: Int

    static var saved: Goals {
        let d = UserDefaults.standard
        return Goals(
            heightCm: d.object(forKey: heightKey) as? Double ?? 172,
            goalWeight: d.object(forKey: goalWeightKey) as? Double ?? 68,
            weeklyLoss: d.object(forKey: weeklyLossKey) as? Double ?? 0.5,
            steps: d.object(forKey: stepKey) as? Int ?? 8000,
            activeCalories: d.object(forKey: activeKey) as? Int ?? 400,
            exerciseMinutes: d.object(forKey: exerciseKey) as? Int ?? 30,
            cardioWeeklyMinutes: d.object(forKey: cardioKey) as? Int ?? 150
        )
    }

    /// Mifflin–St Jeor resting energy, kcal/day.
    static func basalMetabolicRate(weight: Double, heightCm: Double, age: Int, isMale: Bool) -> Double {
        10 * weight + 6.25 * heightCm - 5 * Double(age) + (isMale ? 5 : -161)
    }

    /// Daily intake target: lightly active maintenance (BMR × 1.2) minus the deficit
    /// for the planned weekly loss (7,700 kcal per kg), never below a safe floor.
    func intakeTarget(profile: BodyProfile) -> Double {
        let maintenance = Goals.basalMetabolicRate(weight: profile.weight, heightCm: heightCm, age: profile.age, isMale: profile.isMale) * 1.2
        let deficit = weeklyLoss * 7700 / 7
        let floor: Double = profile.isMale ? 1500 : 1200
        return max(maintenance - deficit, floor)
    }
}

/// Today's calories in the familiar diet-app form: goal − food + exercise = remaining.
struct CalorieBudget {
    let target: Double
    let eaten: Double
    let exercise: Double

    var remaining: Double { target - eaten + exercise }

    @MainActor
    init(goals: Goals = .saved, profile: BodyProfile = .saved, health: HealthData) {
        target = goals.intakeTarget(profile: profile)
        eaten = health.todayEaten
        exercise = health.todayActive
    }
}

/// Running burns about 9.8 METs; used to turn extra calories into minutes of running.
func runningMinutes(toBurn kcal: Double, weight: Double) -> Int {
    guard kcal > 0, weight > 0 else { return 0 }
    return Int((kcal / (9.8 * weight / 60)).rounded(.up))
}
