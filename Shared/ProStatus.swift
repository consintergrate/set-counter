import Foundation

/// Whether Pro is unlocked, copied into the App Group by the app so the widgets
/// can show their locked face without StoreKit.
enum ProStatus {
    private static let key = "isPro"

    static var isUnlocked: Bool {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.bool(forKey: key) ?? false
    }

    static func set(_ unlocked: Bool) {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(unlocked, forKey: key)
    }
}
