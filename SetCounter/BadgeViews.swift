import SwiftUI

/// A hexagon with softened corners.
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let corners = (0..<6).map { index -> CGPoint in
            let angle = Double(index) * .pi / 3 - .pi / 2
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        var path = Path()
        let rounding = radius * 0.18
        for index in 0..<6 {
            let corner = corners[index]
            let previous = corners[(index + 5) % 6]
            let next = corners[(index + 1) % 6]
            func toward(_ point: CGPoint) -> CGPoint {
                let dx = point.x - corner.x, dy = point.y - corner.y
                let length = sqrt(dx * dx + dy * dy)
                return CGPoint(x: corner.x + dx / length * rounding, y: corner.y + dy / length * rounding)
            }
            let start = toward(previous), end = toward(next)
            if index == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: corner)
        }
        path.closeSubpath()
        return path
    }
}

/// The badge itself: a tinted hexagon with its symbol, grey while locked.
struct BadgeMedallion: View {
    let badge: BadgeDefinition
    let earned: Bool
    var size: CGFloat = 64

    var body: some View {
        let colors = earned ? badge.tier.colors : [Color(.systemGray4), Color(.systemGray5)]
        ZStack {
            HexagonShape()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            HexagonShape()
                .stroke(.white.opacity(earned ? 0.55 : 0.3), lineWidth: size * 0.04)
                .padding(size * 0.08)
            Image(systemName: badge.systemImage)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(earned ? Color.white : Color(.systemGray))
                .shadow(color: .black.opacity(earned ? 0.25 : 0), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: earned ? colors.last!.opacity(0.35) : .clear, radius: size * 0.1, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

/// All badges by family: earned ones in color, the rest grey with how far along they are.
struct BadgeCollectionView: View {
    @State private var selected: BadgeDefinition?
    private let center = BadgeCenter.shared

    var body: some View {
        let earnedCount = BadgeDefinition.all.filter { center.earned[$0.id] != nil }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(earnedCount)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("/ \(BadgeDefinition.all.count)개 획득").font(.headline).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(earnedCount), total: Double(BadgeDefinition.all.count))
                        .tint(.orange)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))

                ForEach(BadgeFamily.allCases) { family in
                    let badges = BadgeDefinition.all.filter { $0.family == family }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(family.title).font(.title3.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 16) {
                            ForEach(badges) { badge in
                                Button {
                                    selected = badge
                                } label: {
                                    cell(badge)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("배지")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { badge in
            BadgeDetailSheet(badge: badge)
        }
        .onAppear { center.markAllSeen() }
    }

    private func cell(_ badge: BadgeDefinition) -> some View {
        let earned = center.earned[badge.id]
        let progress = center.progress[badge.id] ?? BadgeProgress()
        return VStack(spacing: 6) {
            BadgeMedallion(badge: badge, earned: earned != nil, size: 64)
            Text(badge.title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let earned {
                Text(earned.earnedAt.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView(value: progress.fraction(goal: badge.goal))
                    .tint(.orange)
                    .frame(width: 56)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title), \(earned != nil ? String(localized: "획득") : badge.progressText(progress.value))")
    }
}

struct BadgeDetailSheet: View {
    let badge: BadgeDefinition
    @Environment(\.dismiss) private var dismiss
    private let center = BadgeCenter.shared

    var body: some View {
        let earned = center.earned[badge.id]
        let progress = center.progress[badge.id] ?? BadgeProgress()
        VStack(spacing: 18) {
            BadgeMedallion(badge: badge, earned: earned != nil, size: 120)
                .padding(.top, 28)
            VStack(spacing: 6) {
                Text(badge.tier.title)
                    .font(.caption.bold())
                    .foregroundStyle(earned != nil ? badge.tier.colors.last! : Color.secondary)
                Text(badge.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(badge.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let earned {
                Label(earned.earnedAt.formatted(date: .long, time: .omitted), systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Color.green.readable)
            } else {
                VStack(spacing: 6) {
                    ProgressView(value: progress.fraction(goal: badge.goal)).tint(.orange)
                    Text(badge.progressText(progress.value)).font(.subheadline.bold()).monospacedDigit()
                }
                .padding(.horizontal, 40)
            }
            Spacer()
            Button("닫기") { dismiss() }
                .buttonStyle(.bordered)
                .padding(.bottom)
        }
        .padding(.horizontal)
        .presentationDetents([.medium])
    }
}

/// Home's badge card: count, the latest few, and new ones called out.
struct BadgeHomeCard: View {
    private let center = BadgeCenter.shared

    var body: some View {
        let earned = BadgeDefinition.all.filter { center.earned[$0.id] != nil }
        let latest = earned.sorted { (center.earned[$0.id]?.earnedAt ?? .distantPast) > (center.earned[$1.id]?.earnedAt ?? .distantPast) }
        let newCount = center.unseen.count
        let next = nextBadge
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                if let top = latest.first {
                    BadgeMedallion(badge: top, earned: true, size: 54)
                } else if let next {
                    BadgeMedallion(badge: next.badge, earned: false, size: 54)
                }
                if newCount > 0 {
                    Text("\(newCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                        .offset(x: 6, y: -4)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(newCount > 0 ? String(localized: "새 배지 \(newCount)개!") : String(localized: "배지 \(earned.count)/\(BadgeDefinition.all.count)"))
                    .font(.headline)
                if let next {
                    Text(String(localized: "다음: \(next.badge.title) · \(next.badge.progressText(next.progress.value))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("모든 배지를 모았어요!").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
    }

    /// The unearned badge closest to done.
    private var nextBadge: (badge: BadgeDefinition, progress: BadgeProgress)? {
        BadgeDefinition.all
            .filter { center.earned[$0.id] == nil }
            .map { ($0, center.progress[$0.id] ?? BadgeProgress()) }
            .max { $0.1.fraction(goal: $0.0.goal) < $1.1.fraction(goal: $1.0.goal) }
    }
}

/// New badges on the workout's finish screen, popping in one after another.
struct NewBadgesBanner: View {
    let badges: [BadgeDefinition]
    var hapticsOn = true

    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            Text(badges.count == 1 ? String(localized: "새 배지를 받았어요!") : String(localized: "새 배지 \(badges.count)개를 받았어요!"))
                .font(.headline)
            // A few fit centered; more scroll sideways.
            if badges.count <= 3 {
                HStack(alignment: .top, spacing: 16) { medals }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) { medals }.padding(.horizontal, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { shown = true }
        .sensoryFeedback(trigger: shown) { _, isShown in hapticsOn && isShown ? .success : nil }
    }

    private var medals: some View {
        ForEach(Array(badges.enumerated()), id: \.element.id) { index, badge in
            VStack(spacing: 6) {
                BadgeMedallion(badge: badge, earned: true, size: 72)
                    .scaleEffect(shown ? 1 : 0.2)
                    .rotation3DEffect(.degrees(shown ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.15 + Double(index) * 0.15), value: shown)
                Text(badge.title)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 100)
            }
        }
    }
}
