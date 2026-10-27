import SwiftUI

/// A titled white card, the building block of the daily and weekly reports.
struct ReportCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    var color: Color = .primary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(color)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

/// One number with an optional progress ring toward a goal and the change from the
/// period before.
struct ReportTile: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String?
    /// 0...1 toward the goal; nil hides the ring.
    var progress: Double?
    var color: Color = .accentColor
    /// The goal is a ceiling (food eaten): going past it turns the ring red.
    var goalIsLimit = false
    var delta: Delta?

    struct Delta {
        let text: String
        let isUp: Bool
        /// Going up is good for steps and workouts, not for food eaten.
        var upIsGood = true
    }

    var body: some View {
        HStack(spacing: 12) {
            if let progress {
                let over = goalIsLimit && progress > 1
                let ringColor = over ? Color.red : color
                ZStack {
                    Circle().stroke(ringColor.opacity(0.18), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if progress >= 1 {
                        Image(systemName: over ? "exclamationmark" : "checkmark").font(.caption.bold()).foregroundStyle(ringColor)
                    }
                }
                .frame(width: 38, height: 38)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(value)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let delta {
                    Text("\(delta.isUp ? "▲" : "▼") \(delta.text)")
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(delta.isUp == delta.upIsGood ? .green : .orange)
                } else if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    // Keeps the tiles in a row the same height.
                    Text(" ").font(.caption2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// "‹ 10월 19일 – 25일 ›": steps through days or weeks.
struct PeriodSwitcher: View {
    let title: String
    var subtitle: String?
    let canGoBack: Bool
    let canGoForward: Bool
    /// Going further back needs Pro; the button opens the paywall instead.
    var backIsLocked = false
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if backIsLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                                .offset(x: -6, y: 8)
                        }
                    }
            }
            .disabled(!canGoBack)
            .accessibilityLabel(backIsLocked ? Text("이전 · Pro 기능") : Text("이전"))
            Spacer()
            VStack(spacing: 2) {
                Text(title).font(.headline).monospacedDigit()
                if let subtitle {
                    Text(subtitle).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            Spacer()
            Button(action: onForward) {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("다음")
        }
    }
}

/// Plain-language lines at the top of a report.
struct SummaryLines: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Muscle → sets as horizontal bars, with the weekly 10-set mark.
struct MuscleBars: View {
    let sets: [Muscle: Int]

    var body: some View {
        let muscles = Muscle.tracked.filter { sets[$0, default: 0] > 0 }
        let top = max(sets.values.max() ?? 0, 10)
        VStack(spacing: 8) {
            ForEach(muscles) { muscle in
                let count = sets[muscle, default: 0]
                HStack(spacing: 8) {
                    Text(muscle.title).font(.caption).frame(width: 36, alignment: .leading)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(count >= 10 ? Color.green : Color.orange)
                                    .frame(width: max(geometry.size.width * Double(count) / Double(top), 6))
                            }
                    }
                    .frame(height: 8)
                    Text(String(localized: "\(count)세트")).font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}
