import AlarmKit
import SwiftUI

struct RestAlarmMetadata: AlarmMetadata {}

/// System alarm (AlarmKit) used while the app is in the background or the
/// screen is locked, since the in-app timer can't run once the app is suspended.
@MainActor
enum LockScreenAlarm {
    private static var currentID: UUID?

    static func requestAuthorization() async {
        guard AlarmManager.shared.authorizationState == .notDetermined else { return }
        _ = try? await AlarmManager.shared.requestAuthorization()
    }

    static func schedule(at date: Date, nextSet: Int) {
        cancel()
        guard AlarmManager.shared.authorizationState == .authorized else { return }

        let alert = AlarmPresentation.Alert(title: "휴식 끝! \(nextSet)세트 시작")
        let attributes = AlarmAttributes<RestAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: RestAlarmMetadata(),
            tintColor: .orange
        )
        let id = UUID()
        currentID = id
        Task {
            do {
                _ = try await AlarmManager.shared.schedule(
                    id: id,
                    configuration: .alarm(schedule: .fixed(date), attributes: attributes)
                )
                // Cancelled while scheduling was in flight.
                if currentID != id { try? AlarmManager.shared.cancel(id: id) }
            } catch {
                if currentID == id { currentID = nil }
            }
        }
    }

    static func cancel() {
        guard let id = currentID else { return }
        currentID = nil
        try? AlarmManager.shared.stop(id: id)
        try? AlarmManager.shared.cancel(id: id)
    }
}
