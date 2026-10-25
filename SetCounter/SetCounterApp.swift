import SwiftData
import SwiftUI

@main
struct SetCounterApp: App {
    /// Pinned to the app's own container: with an App Group entitlement SwiftData would
    /// otherwise default to the group container and existing records would vanish.
    private let container: ModelContainer = {
        if let container = try? ModelContainer(for: WorkoutRecord.self, SetEntry.self, ExerciseProfile.self, configurations: ModelConfiguration(groupContainer: .none)) {
            return container
        }
        // The store couldn't be opened (e.g. a failed migration). Run on an in-memory store
        // instead of crashing on every launch; the file on disk is left untouched.
        do {
            return try ModelContainer(for: WorkoutRecord.self, SetEntry.self, ExerciseProfile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        } catch {
            fatalError("Could not create an in-memory workout store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @AppStorage("theme") private var theme = ThemeChoice.system.rawValue
    @AppStorage("accent") private var accent = AccentChoice.blue.rawValue

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

    var body: some View {
        TabView {
            Tab("홈", systemImage: "house.fill") {
                HomeView()
            }
            Tab("기록", systemImage: "calendar") {
                NavigationStack { HistoryView() }
            }
            Tab("통계", systemImage: "chart.bar.fill") {
                NavigationStack { StatsView() }
            }
            Tab("설정", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tint((AccentChoice(rawValue: accent) ?? .blue).color)
        .preferredColorScheme((ThemeChoice(rawValue: theme) ?? .system).colorScheme)
        .task(id: records.count) {
            // Anything derived from records: reminders and the home screen widget.
            await RoutineNotifications.reschedule(records: records)
            WidgetSnapshot.write(records: records)
        }
        #if DEBUG
        // `-demoHeartRate 126` feeds a fake sensor, for simulator screenshots.
        .task {
            // Launch arguments arrive as strings; integer(forKey:) converts them.
            let base = UserDefaults.standard.integer(forKey: "demoHeartRate")
            guard base > 0 else { return }
            while !Task.isCancelled {
                HeartRateMonitor.shared.report(base + Int.random(in: -3...3), source: "Demo")
                try? await Task.sleep(for: .seconds(2))
            }
        }
        #endif
    }
}
