import SwiftData
import SwiftUI

struct WorkoutView: View {
    let session: WorkoutSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @AppStorage("weeklyGoal") private var weeklyGoal = 4
    @AppStorage("accent") private var accent = AccentChoice.blue.rawValue
    @AppStorage("keepScreenOn") private var keepScreenOn = false
    @AppStorage("showMetrics") private var showMetrics = true
    @AppStorage("showElapsed") private var showElapsed = true
    @AppStorage("hapticsOn") private var hapticsOn = true
    @State private var confirmingEnd = false
    @State private var saved = false
    @State private var shownAlert: WorkoutSession.RecordAlert?
    @State private var showingGuide = false
    /// Badges this workout earned, worked out once it's saved.
    @State private var newBadges: [BadgeDefinition] = []

    private var isAlarming: Bool { session.phase == .alarming }
    private var accentColor: Color { AccentChoice.effective(accent).color }

    var body: some View {
        VStack(spacing: 20) {
            header
            SetDots(total: session.totalSets, completed: session.completedSets, onAccent: isAlarming)
            if showMetrics, session.startedAt != nil, session.phase != .finished {
                metrics
            }
            Spacer()
            content
            Spacer()
        }
        .padding()
        .background((isAlarming ? Color.orange : Color(.systemBackground)).ignoresSafeArea())
        // Full-screen covers don't reliably inherit the app tint.
        .tint(accentColor)
        .animation(.default, value: session.phase)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenOn }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, newPhase in
            session.scenePhaseChanged(newPhase)
        }
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .finished { save() }
        }
        .overlay(alignment: .top) {
            if let shownAlert {
                Label(shownAlert.message, systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.orange.gradient, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .onChange(of: session.recordAlert) { _, alert in
            guard let alert else { return }
            withAnimation(.spring) { shownAlert = alert }
            Task {
                try? await Task.sleep(for: .seconds(3))
                if shownAlert == alert { withAnimation { shownAlert = nil } }
            }
        }
        .sensoryFeedback(trigger: session.recordAlert) { _, alert in hapticsOn && alert != nil ? .impact(weight: .heavy) : nil }
        .confirmationDialog("운동을 종료할까요?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("종료", role: .destructive, action: close)
        } message: {
            if session.completedSets > 0 {
                Text("완료한 \(session.completedSets)세트는 기록에 저장돼요.")
            }
        }
    }

    private var header: some View {
        HStack {
            Button("종료") {
                if session.phase == .finished || session.phase == .ready { close() } else { confirmingEnd = true }
            }
            .tint(isAlarming ? .white : accentColor)
            Spacer()
            Group {
                if showElapsed, session.startedAt != nil, session.phase != .finished {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Label(formatClock(session.duration), systemImage: "stopwatch")
                            .monospacedDigit()
                    }
                }
                Spacer()
                Text("\(session.completedSets) / \(session.totalSets) 완료")
                    .monospacedDigit()
            }
            .foregroundStyle(isAlarming ? Color.white : Color.secondary)
            Button {
                showingGuide = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .tint(isAlarming ? .white : accentColor)
            .accessibilityLabel("사용법")
        }
        .sheet(isPresented: $showingGuide) {
            OnboardingView { showingGuide = false }
        }
    }

    private var metrics: some View {
        VStack(spacing: 4) {
            HStack(spacing: 24) {
                Label(session.heartRate.map { "\($0)" } ?? "--", systemImage: "heart.fill")
                    .foregroundStyle(isAlarming ? .white : Color.red.readable)
                    .symbolEffect(.pulse, isActive: session.heartRate != nil)
                Label("\(Int(session.calories).formatted()) kcal", systemImage: "flame.fill")
                    .foregroundStyle(isAlarming ? .white : Color.orange.readable)
            }
            .font(.title3.bold())
            .monospacedDigit()
            .contentTransition(.numericText())
            // Where the heart rate comes from, so a missing Watch or strap is obvious.
            Group {
                if HealthWorkout.shared.isWatchConnected {
                    Label("Apple Watch 연결됨", systemImage: "applewatch")
                } else if session.heartRate != nil, let source = HeartRateMonitor.shared.source {
                    Text(source)
                } else {
                    Text("심박수 없음 · 기본 강도로 칼로리를 계산해요")
                }
            }
            .font(.caption)
            .foregroundStyle(isAlarming ? Color.white.opacity(0.85) : Color.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .ready:
            setPrompt(subtitle: "준비되면 시작을 눌러요", buttonTitle: "시작", action: session.start)
        case .exercising:
            setPrompt(subtitle: "세트를 마치면 눌러요", buttonTitle: "세트 완료", action: session.completeSet)
        case .resting(let end):
            VStack(spacing: 24) {
                RestTimerView(
                    end: end,
                    total: TimeInterval(session.restSeconds),
                    nextSet: session.currentSet,
                    onAdd: { session.addRestTime(15) },
                    onSkip: session.skipRest
                )
                if let last = session.entries.last {
                    VStack(spacing: 8) {
                        Text("방금 한 \(session.completedSets)세트").font(.subheadline).foregroundStyle(.secondary)
                        SetValueStepper(
                            weight: last.weight,
                            reps: last.reps,
                            onWeight: { session.adjustLastSet(weightBy: $0) },
                            onReps: { session.adjustLastSet(repsBy: $0) }
                        )
                    }
                }
            }
        case .alarming:
            alarming
        case .finished:
            finished
        }
    }

    private var exerciseName: String {
        session.exercise.isEmpty ? String(localized: "운동") : session.exercise
    }

    private var exerciseLine: some View {
        VStack(spacing: 4) {
            if !session.routineName.isEmpty {
                Text(session.routineName)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(accentColor)
            }
            Text(exerciseName)
                .font(.title2.bold())
            SetValueStepper(
                weight: session.currentWeight,
                reps: session.currentReps,
                onWeight: { session.currentWeight = max(0, session.currentWeight + $0) },
                onReps: { session.currentReps = max(1, session.currentReps + $0) }
            )
            .padding(.top, 4)
        }
    }

    private func setPrompt(subtitle: LocalizedStringKey, buttonTitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(spacing: 24) {
            exerciseLine
            VStack(spacing: 8) {
                // Own key: in English this is "Set 2", while "%lld세트" elsewhere means "2 sets".
                Text(String(localized: "workout.currentSet", defaultValue: "\(session.currentSet)세트"))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
            Button(action: action) {
                Text(buttonTitle)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .frame(width: 200, height: 200)
                    .background(Circle().fill(.tint))
            }
            .sensoryFeedback(trigger: session.completedSets) { _, _ in hapticsOn ? .success : nil }
            .sensoryFeedback(trigger: session.startedAt) { _, _ in hapticsOn ? .impact : nil }
        }
    }

    private var alarming: some View {
        Button(action: session.dismissAlarm) {
            VStack(spacing: 16) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 64))
                    .symbolEffect(.wiggle, options: .repeating)
                Text("휴식 끝!").font(.system(size: 56, weight: .bold, design: .rounded))
                Text("\(session.currentSet)세트 시작 · 탭해서 끄기").font(.title3)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var finished: some View {
        VStack(spacing: 24) {
            Image(systemName: "trophy.fill")
                .font(.system(size: newBadges.isEmpty ? 72 : 48))
                .foregroundStyle(.yellow)
            Text("운동 완료!").font(.system(size: newBadges.isEmpty ? 44 : 36, weight: .bold, design: .rounded))
            if !newBadges.isEmpty {
                NewBadgesBanner(badges: newBadges, hapticsOn: hapticsOn)
            }
            VStack(spacing: 12) {
                SummaryRow(title: "운동", value: exerciseName)
                SummaryRow(title: "세트", value: setsSummary(session.entries))
                if Set(session.entries).count > 1 {
                    Text(session.entries.map { "\(formatWeight($0.weight))×\($0.reps)" }.joined(separator: " · "))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                SummaryRow(title: "운동 시간", value: formatClock(session.duration))
                if session.volume > 0 {
                    SummaryRow(title: "총 볼륨", value: formatMass(session.volume))
                }
                SummaryRow(title: "칼로리 (추정)", value: "\(Int(session.calories).formatted()) kcal")
                if session.maxHeartRate > 0 {
                    SummaryRow(title: "평균 / 최대 심박", value: "\(session.averageHeartRate) / \(session.maxHeartRate) bpm")
                }
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            WeeklyGoalGauge(done: Routine.weeklyDays(records: records), goal: weeklyGoal)
                .padding(.horizontal)
            Button("처음으로", action: close)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func save() {
        guard !saved, session.completedSets > 0, let startedAt = session.startedAt else { return }
        saved = true
        let record = WorkoutRecord(
            date: startedAt,
            exercise: session.exercise,
            sets: session.completedSets,
            weight: 0,
            reps: 0,
            duration: session.duration,
            calories: session.calories,
            averageHeartRate: session.averageHeartRate,
            maxHeartRate: session.maxHeartRate,
            routineIndex: session.routineIndex,
            routineName: session.routineName
        )
        modelContext.insert(record)
        record.replaceSets(session.entries, in: modelContext)
        // Write now rather than at the next autosave, in case the app is closed right away.
        try? modelContext.save()
        checkBadges(including: record)
    }

    private func close() {
        session.end()
        save()
        BadgeCenter.shared.markSeen(newBadges.map(\.id))
        dismiss()
    }

    /// After saving, finds the badges reached by this workout to celebrate them here.
    /// The query may not have picked up the new record yet, so it's added if missing.
    private func checkBadges(including record: WorkoutRecord) {
        guard let startedAt = session.startedAt else { return }
        let all = records.contains { $0.persistentModelID == record.persistentModelID } ? records : [record] + records
        BadgeCenter.shared.update(records: all, health: HealthData.shared)
        withAnimation { newBadges = BadgeCenter.shared.unseen(since: startedAt) }
    }
}

private struct SummaryRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
    }
}

private struct SetDots: View {
    let total: Int
    let completed: Int
    let onAccent: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(fill(done: index < completed))
                    .frame(height: 8)
            }
        }
    }

    private func fill(done: Bool) -> AnyShapeStyle {
        if onAccent { return AnyShapeStyle(done ? Color.white : .white.opacity(0.35)) }
        return done ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.25))
    }
}

private struct RestTimerView: View {
    let end: Date
    let total: TimeInterval
    let nextSet: Int
    let onAdd: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("쉬는 시간").font(.title2.bold())
                Text("다음: \(nextSet)세트").foregroundStyle(.secondary)
            }

            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                let remaining = max(0, end.timeIntervalSince(context.date))
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: min(1, remaining / max(total, remaining)))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(formatClock(remaining.rounded(.up)))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 230, height: 230)
            }

            HStack(spacing: 16) {
                Button("+15초", action: onAdd)
                    .buttonStyle(.bordered)
                Button("건너뛰기", action: onSkip)
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }
}


/// Compact −/+ controls for one set's weight and reps.
struct SetValueStepper: View {
    let weight: Double
    let reps: Int
    /// Change in kg (one plate step in the display unit).
    let onWeight: (Double) -> Void
    let onReps: (Int) -> Void

    @AppStorage(WeightUnit.key) private var unitRaw = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        HStack(spacing: 10) {
            pill(formatWeight(weight, unit: unit), minus: String(localized: "무게 줄이기"), plus: String(localized: "무게 늘리기")) {
                onWeight(unit.toKg($0 ? unit.step : -unit.step))
            }
            pill(String(localized: "\(reps)회"), minus: String(localized: "횟수 줄이기"), plus: String(localized: "횟수 늘리기")) {
                onReps($0 ? 1 : -1)
            }
        }
    }

    private func pill(_ label: String, minus: String, plus: String, change: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 4) {
            Button { change(false) } label: { Image(systemName: "minus").frame(width: 32, height: 32).contentShape(Rectangle()) }
                .accessibilityLabel(minus)
            Text(label)
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 64)
                .contentTransition(.numericText())
            Button { change(true) } label: { Image(systemName: "plus").frame(width: 32, height: 32).contentShape(Rectangle()) }
                .accessibilityLabel(plus)
        }
        // Plain buttons only hit-test drawn pixels, so the thin "−" needs a full tap square.
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
