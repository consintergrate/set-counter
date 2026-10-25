import SwiftUI

/// Three short pages on how the counter works, shown once after the first launch
/// and again from Settings → 사용법.
struct OnboardingView: View {
    static let doneKey = "onboardingDone"

    let onDone: () -> Void

    @AppStorage("accent") private var accent = AccentChoice.blue.rawValue
    @State private var page = 0

    private var color: Color { (AccentChoice(rawValue: accent) ?? .blue).color }

    private struct Page {
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let pages = [
        Page(title: "세트는 한 번만 누르면 끝",
             body: "시작을 누르고 운동하세요. 세트를 마칠 때마다 큰 버튼을 한 번 누르면 세트 수가 올라가고 휴식 타이머가 바로 시작돼요."),
        Page(title: "쉬는 시간은 알아서",
             body: "휴식이 끝나면 알람이 울려요. 음악은 알람이 울리는 동안만 잠깐 멈추고, 화면을 잠가도 울려요. 쉬는 동안 방금 한 세트의 무게와 횟수를 고칠 수 있어요."),
        Page(title: "코치가 하루를 챙겨요",
             body: "건강 앱을 연결하면 걸음, 칼로리, 체중, 나이키 런 클럽 같은 다른 앱의 러닝까지 모아 알려드려요. 목표 체중은 홈의 체중 카드를 눌러 언제든 바꿀 수 있어요."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages.count - 1 {
                    Button("건너뛰기", action: onDone)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 44)
            .padding(.horizontal)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 28) {
                        Spacer(minLength: 0)
                        illustration(for: index)
                            .frame(height: 240)
                        VStack(spacing: 12) {
                            Text(pages[index].title)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)
                            Text(pages[index].body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 32)
                        Spacer(minLength: 0)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? AnyShapeStyle(color) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .padding(.bottom, 20)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? "다음" : "시작하기")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(color, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func illustration(for index: Int) -> some View {
        switch index {
        case 0: CounterDemo(color: color)
        case 1: RestDemo(color: color)
        default: AssistantDemo()
        }
    }
}

/// The big button being tapped and the set number counting up.
private struct CounterDemo: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var set = 1
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 18) {
            Text(String(localized: "workout.currentSet", defaultValue: "\(set)세트"))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            ZStack {
                Circle().fill(color)
                Text("세트 완료")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 140, height: 140)
            .scaleEffect(pressed ? 0.9 : 1)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.primary.opacity(0.8))
                    .offset(x: 10, y: pressed ? 4 : 18)
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeIn(duration: 0.12)) { pressed = true }
                try? await Task.sleep(for: .seconds(0.14))
                withAnimation(.spring(duration: 0.3)) {
                    pressed = false
                    set = set % 5 + 1
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A rest ring draining, then the alarm bell.
private struct RestDemo: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var remaining = 1.0

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                if remaining < 0.02 {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(color)
                        .symbolEffect(.wiggle, options: .repeating)
                    Text("휴식 끝!").font(.title3.bold())
                } else {
                    Text(formatClock(remaining * 90))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("쉬는 시간").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 200, height: 200)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                remaining = 1
                // Ninety seconds told in three.
                for step in stride(from: 1.0, through: 0, by: -0.02) {
                    withAnimation(.linear(duration: 0.06)) { remaining = step }
                    try? await Task.sleep(for: .seconds(0.06))
                }
                try? await Task.sleep(for: .seconds(1.6))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The kinds of data the coach brings together.
private struct AssistantDemo: View {
    private let items: [(icon: String, title: LocalizedStringKey, color: Color)] = [
        ("flame.fill", "칼로리", .orange),
        ("figure.run", "유산소", .teal),
        ("scalemass.fill", "체중", .blue),
        ("shoeprints.fill", "걸음", .green),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            LazyVGrid(columns: [GridItem(.fixed(120)), GridItem(.fixed(120))], spacing: 12) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    VStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.title2)
                            .foregroundStyle(item.color)
                        Text(item.title).font(.subheadline.bold())
                    }
                    .frame(width: 120, height: 76)
                    .background(item.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
