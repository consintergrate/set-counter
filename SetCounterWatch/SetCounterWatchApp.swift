import HealthKit
import SwiftUI
import WatchKit

@main
struct SetCounterWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// The iPhone app asks for this with `startWatchApp(with:)` when a workout starts.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WatchWorkout.shared.start(workoutConfiguration) }
    }
}
