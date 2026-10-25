import SwiftUI

struct WatchContentView: View {
    private let workout = WatchWorkout.shared
    @State private var confirmingEnd = false

    var body: some View {
        if workout.isRunning {
            running
        } else {
            idle
        }
    }

    private var idle: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text("세트 카운터").font(.headline)
            Text("iPhone에서 운동을 시작하면 여기서 심박수를 재서 보내고, 휴식이 끝나면 손목을 톡 쳐서 알려줘요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .task { await workout.requestAuthorization() }
    }

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, isActive: workout.heartRate != nil)
                        Text(workout.heartRate.map { "\($0)" } ?? "--")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("bpm").font(.caption2).foregroundStyle(.secondary)
                    }

                    if let restEnd = workout.restEnd, restEnd > context.date {
                        Text("휴식 \(clock(restEnd.timeIntervalSince(context.date)))")
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    } else if workout.setsTotal > 0 {
                        Text("\(workout.setsDone) / \(workout.setsTotal) 세트")
                            .font(.title3.bold())
                            .monospacedDigit()
                    }

                    if !workout.exercise.isEmpty {
                        Text(workout.exercise)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let start = workout.startDate {
                        Text(clock(context.date.timeIntervalSince(start)))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Button("측정 끝내기", role: .destructive) { confirmingEnd = true }
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog("워치 측정을 끝낼까요?", isPresented: $confirmingEnd) {
            Button("끝내기", role: .destructive) {
                Task { await workout.end(save: true) }
            }
        } message: {
            Text("iPhone의 세트 카운트는 그대로 이어져요.")
        }
    }

    private func clock(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
