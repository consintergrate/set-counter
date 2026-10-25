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

    private var isAlarming: Bool { session.phase == .alarming }
    private var accentColor: Color { (AccentChoice(rawValue: accent) ?? .blue).color }

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
        }
    }

    private var metrics: some View {
        HStack(spacing: 24) {
            Label(session.heartRate.map { "\($0)" } ?? "--", systemImage: "heart.fill")
                .foregroundStyle(isAlarming ? .white : .red)
                .symbolEffect(.pulse, isActive: session.heartRate != nil)
            Label("\(Int(session.calories).formatted()) kcal", systemImage: "flame.fill")
                .foregroundStyle(isAlarming ? .white : .orange)
        }
        .font(.title3.bold())
        .monospacedDigit()
        .contentTransition(.numericText())
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .ready:
            setPrompt(subtitle: "준비되면 시작을 눌러요", buttonTitle: "시작", action: session.start)
        case .exercising:
            setPrompt(subtitle: "운동 중", buttonTitle: "세트 완료", action: session.completeSet)
        case .resting(let end):
            RestTimerView(
                end: end,
                total: TimeInterval(session.restSeconds),
                nextSet: session.currentSet,
                onAdd: { session.addRestTime(15) },
                onSkip: session.skipRest
            )
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
            Text("\(formatWeight(session.weight)) × \(session.reps)회")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func setPrompt(subtitle: LocalizedStringKey, buttonTitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(spacing: 32) {
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
                    .frame(width: 220, height: 220)
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
                .font(.system(size: 72))
                .foregroundStyle(.yellow)
            Text("운동 완료!").font(.system(size: 44, weight: .bold, design: .rounded))
            VStack(spacing: 12) {
                SummaryRow(title: "운동", value: exerciseName)
                SummaryRow(title: "세트", value: String(localized: "\(formatWeight(session.weight)) × \(session.reps)회 × \(session.completedSets)세트"))
                SummaryRow(title: "운동 시간", value: formatClock(session.duration))
                if session.weight > 0 {
                    SummaryRow(title: "총 볼륨", value: formatMass(session.weight * Double(session.reps * session.completedSets)))
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
        modelContext.insert(WorkoutRecord(
            date: startedAt,
            exercise: session.exercise,
            sets: session.completedSets,
            weight: session.weight,
            reps: session.reps,
            duration: session.duration,
            calories: session.calories,
            averageHeartRate: session.averageHeartRate,
            maxHeartRate: session.maxHeartRate,
            routineIndex: session.routineIndex,
            routineName: session.routineName
        ))
    }

    private func close() {
        session.end()
        save()
        dismiss()
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
        VStack(spacing: 32) {
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
                .frame(width: 260, height: 260)
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
