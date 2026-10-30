import SwiftData
import UserNotifications
import WidgetKit

/// "모든 데이터 삭제": everything the app keeps on this iPhone, back to a fresh install.
/// Pro purchases stay with the Apple Account and come back on their own.
@MainActor
enum DataEraser {
    static func eraseAll(context: ModelContext, includingHealth: Bool) async {
        // Badges first: screens still showing the old records must not earn them again.
        BadgeCenter.shared.erase()

        // Batch deletes skip the cascade rule, so per-set rows go explicitly.
        try? context.delete(model: WorkoutRecord.self)
        try? context.delete(model: SetEntry.self)
        try? context.delete(model: ExerciseProfile.self)
        try? context.save()

        // Settings, body info, goals, routines, foods, and the widgets' copies.
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.removePersistentDomain(forName: WidgetSnapshot.appGroup)

        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
        CSVExporter.removeExport()
        Backup.removeExports()

        if includingHealth { await HealthData.shared.deleteOwnSamples() }
        await HealthData.shared.refresh()
        #if DEBUG
        ProStore.shared.debugUnlocked = false
        #endif
        await ProStore.shared.refreshEntitlements()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
