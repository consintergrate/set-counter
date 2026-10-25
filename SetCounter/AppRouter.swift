import SwiftUI
import UserNotifications

/// Screens that can be opened from outside the view tree, such as a notification tap.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var showingWeeklyReport = false
}

/// Routes notification taps and lets reminders show while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.identifier == RoutineNotifications.weeklyReportID {
            await MainActor.run { AppRouter.shared.showingWeeklyReport = true }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
