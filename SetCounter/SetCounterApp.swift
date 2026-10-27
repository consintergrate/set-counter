import SwiftData
import SwiftUI

@main
struct SetCounterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
    /// The opening animation plays once per launch, over the already-loaded app.
    @State private var showingSplash = true
    @State private var showingOnboarding = false
    @AppStorage(OnboardingView.doneKey) private var onboardingDone = false
    @State private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

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
        .overlay {
            if showingSplash {
                SplashView {
                    showingSplash = false
                    // First launch: a short guide right after the opening animation.
                    if !onboardingDone { showingOnboarding = true }
                }
            }
        }
        .statusBarHidden(showingSplash)
        .sheet(isPresented: $router.showingWeeklyReport) {
            WeeklyReportView()
        }
        .sheet(isPresented: $router.showingDailyReport) {
            DailyReportView()
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView {
                onboardingDone = true
                showingOnboarding = false
            }
        }
        .tint(AccentChoice.effective(accent).color)
        .preferredColorScheme(ThemeChoice.effective(theme).colorScheme)
        .task(id: records.count) {
            // Anything derived from records: reminders and the home screen widget.
            await RoutineNotifications.reschedule(records: records)
            WidgetSnapshot.write(records: records)
            BadgeCenter.shared.update(records: records, health: HealthData.shared)
        }
        // The widget's accent follows Pro.
        .onChange(of: ProStore.shared.isPro) {
            WidgetSnapshot.write(records: records)
        }
        // Cardio, meals, and weight arrive from Health; they can earn badges too.
        .onChange(of: HealthData.shared.lastRefresh) {
            BadgeCenter.shared.update(records: records, health: HealthData.shared)
        }
        // Runs from Nike Run Club and friends land in Health while we're in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await HealthData.shared.refresh() } }
        }
        .task { await HealthData.shared.refresh() }
        #if DEBUG
        // `-seedHealth YES` fills the simulator's Health store with sample diet data.
        .task {
            if UserDefaults.standard.bool(forKey: "seedHealth") { await HealthData.shared.seedSampleData() }
        }
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
