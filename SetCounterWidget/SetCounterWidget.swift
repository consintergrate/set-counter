import SwiftUI
import WidgetKit

struct RoutineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct RoutineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutineEntry {
        RoutineEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RoutineEntry) -> Void) {
        completion(RoutineEntry(date: Date(), snapshot: WidgetSnapshot.read() ?? .placeholder))
    }

    /// The snapshot already knows how to roll over, so one entry now and one at
    /// midnight keeps the widget right even if the app isn't opened.
    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutineEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read() ?? .placeholder
        let now = Date()
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        let entries = [RoutineEntry(date: now, snapshot: snapshot), RoutineEntry(date: midnight, snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

private func widgetAccent(_ name: String) -> Color {
    switch name {
    case "orange": .orange
    case "green": .green
    case "purple": .purple
    case "pink": .pink
    case "red": .red
    default: .blue
    }
}

struct RoutineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoutineEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var accent: Color { widgetAccent(snapshot.accent) }
    private var days: Int { snapshot.weeklyDays(at: entry.date) }
    private var goalMet: Bool { days >= snapshot.weeklyGoal }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("오늘의 루틴").font(.caption2).foregroundStyle(.secondary)
                Text(snapshot.todayName(at: entry.date)).font(.headline).lineLimit(1)
                Text("이번 주 \(days)/\(snapshot.weeklyGoal)일").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCircular:
            Gauge(value: Double(min(days, snapshot.weeklyGoal)), in: 0...Double(max(snapshot.weeklyGoal, 1))) {
                Image(systemName: "dumbbell.fill")
            } currentValueLabel: {
                Text("\(days)")
            }
            .gaugeStyle(.accessoryCircular)
        case .systemMedium:
            HStack(spacing: 16) {
                header
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    WeekDots(done: snapshot.weekDone(at: entry.date), weekStart: snapshot.weekStart, accent: accent)
                    progress
                }
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 8)
                progress
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(snapshot.splitLabel(at: entry.date), systemImage: "dumbbell.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
            Text("오늘은")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.todayName(at: entry.date))
                .font(.title3.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(goalMet ? String(localized: "목표 달성! 🎉") : String(localized: "이번 주 \(days)/\(snapshot.weeklyGoal)일"))
                .font(.caption.bold())
                .monospacedDigit()
            ProgressView(value: Double(min(days, snapshot.weeklyGoal)), total: Double(max(snapshot.weeklyGoal, 1)))
                .tint(goalMet ? .green : accent)
        }
    }
}

private struct WeekDots: View {
    let done: [Bool]
    let weekStart: Date
    let accent: Color

    var body: some View {
        let calendar = Calendar.current
        HStack(spacing: 6) {
            ForEach(Array(done.enumerated()), id: \.offset) { offset, isDone in
                let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                VStack(spacing: 3) {
                    Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: day) - 1])
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(isDone ? accent : Color.secondary.opacity(0.25))
                        .frame(width: 12, height: 12)
                }
            }
        }
    }
}

struct RoutineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RoutineWidget", provider: RoutineProvider()) { entry in
            RoutineWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("오늘의 루틴")
        .description("오늘 할 부위와 이번 주 목표 진행도를 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct SetCounterWidgetBundle: WidgetBundle {
    var body: some Widget {
        RoutineWidget()
        DietWidget()
    }
}

#Preview(as: .systemMedium) {
    RoutineWidget()
} timeline: {
    RoutineEntry(date: .now, snapshot: .placeholder)
}
