import SwiftUI
import UserNotifications

/// Screens that can be opened from outside the view tree, such as a notification tap.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var showingWeeklyReport = false
    var showingDailyReport = false
}

/// Routes notification taps and lets reminders show while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        HealthWorkout.shared.setUpMirroring()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        switch response.notification.request.identifier {
        case RoutineNotifications.weeklyReportID:
            await MainActor.run { AppRouter.shared.showingWeeklyReport = true }
        case RoutineNotifications.dailyReportID:
            await MainActor.run { AppRouter.shared.showingDailyReport = true }
        default:
            break
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
