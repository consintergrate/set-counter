import SwiftUI
import WidgetKit

struct DietEntry: TimelineEntry {
    let date: Date
    let snapshot: DietSnapshot
}

struct DietProvider: TimelineProvider {
    func placeholder(in context: Context) -> DietEntry {
        DietEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DietEntry) -> Void) {
        completion(DietEntry(date: Date(), snapshot: DietSnapshot.read() ?? .placeholder))
    }

    /// The app refreshes this whenever it reads Health; the midnight entry resets the day.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DietEntry>) -> Void) {
        let snapshot = DietSnapshot.read() ?? .placeholder
        let now = Date()
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [DietEntry(date: now, snapshot: snapshot), DietEntry(date: midnight, snapshot: snapshot)],
                            policy: .after(midnight)))
    }
}

struct DietWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DietEntry

    private var snapshot: DietSnapshot { entry.snapshot }
    private var remaining: Int { Int(snapshot.remaining(at: entry.date)) }
    private var eatenShare: Double { snapshot.eaten(at: entry.date) / max(snapshot.allowance(at: entry.date), 1) }
    private var isOver: Bool { remaining < 0 }
    private var cardio: Int { snapshot.cardioMinutes(at: entry.date) }
    private var cardioShare: Double { Double(cardio) / Double(max(snapshot.cardioGoal, 1)) }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(isOver ? "칼로리 초과" : "남은 칼로리").font(.caption2).foregroundStyle(.secondary)
                Text("\(abs(remaining).formatted())kcal").font(.headline).monospacedDigit()
                Text("유산소 \(cardio)/\(snapshot.cardioGoal)분").font(.caption2).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCircular:
            Gauge(value: min(eatenShare, 1)) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text(abs(remaining) >= 1000 ? "\(abs(remaining) / 1000).\(abs(remaining) % 1000 / 100)k" : "\(abs(remaining))")
            }
            .gaugeStyle(.accessoryCircular)
        case .systemMedium:
            HStack(spacing: 18) {
                calorieRing.frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 8) {
                    term("목표", snapshot.target)
                    term("음식", snapshot.eaten(at: entry.date), sign: "−")
                    term("활동", snapshot.active(at: entry.date), sign: "+")
                    cardioBar
                }
            }
        default:
            VStack(spacing: 8) {
                calorieRing
                cardioBar
            }
        }
    }

    private var calorieRing: some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.2), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(eatenShare, 1))
                .stroke(isOver ? Color.red : Color.orange, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(abs(remaining).formatted())
                    .font(.title3.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isOver ? .red : .primary)
                Text(isOver ? "kcal 초과" : "kcal 남음")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
        }
    }

    private var cardioBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("유산소 \(cardio)/\(snapshot.cardioGoal)분", systemImage: "figure.run")
                .font(.caption2.bold())
                .monospacedDigit()
                .foregroundStyle(cardio >= snapshot.cardioGoal ? .green : .teal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ProgressView(value: min(cardioShare, 1))
                .tint(cardio >= snapshot.cardioGoal ? .green : .teal)
        }
    }

    private func term(_ title: LocalizedStringKey, _ value: Double, sign: String = "") -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(sign)\(Int(value).formatted())").font(.caption.bold()).monospacedDigit()
        }
    }
}

struct DietWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DietWidget", provider: DietProvider()) { entry in
            DietWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("오늘의 칼로리")
        .description("남은 칼로리와 이번 주 유산소를 보여줘요. 앱을 열 때마다 새로 고쳐져요.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

#Preview(as: .systemSmall) {
    DietWidget()
} timeline: {
    DietEntry(date: .now, snapshot: .placeholder)
}
