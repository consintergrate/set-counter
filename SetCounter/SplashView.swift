import SwiftUI

/// Opening animation: an orange arc sweeps around the dumbbell on a deep navy
/// ground, settles into one seamless glowing ring, then the screen fades onto the app.
struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    /// Set when the sweep closes; only brightens the glow on the same ring.
    @State private var complete = false
    @State private var appeared = false
    @State private var showGradient = false
    @State private var opacity: Double = 1
    @State private var finished = false

    /// Same as the launch screen color, so the hand-off from the static launch screen is seamless.
    static let launch = Color(red: 0.071, green: 0.086, blue: 0.227)
    private static let ember = Color(red: 1.0, green: 0.42, blue: 0.10)
    private static let amber = Color(red: 1.0, green: 0.76, blue: 0.42)
    private static let lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Self.launch
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.14, blue: 0.40), Color(red: 0.04, green: 0.05, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(showGradient ? 1 : 0)

            // Warm light behind the ring that builds as it fills.
            RadialGradient(colors: [Self.ember.opacity(0.30), .clear], center: .center, startRadius: 20, endRadius: 280)
                .opacity(progress)

            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: Self.lineWidth)
                    // Colored by screen position, not along the arc, so the closed ring is
                    // the same drawing as the last frame of the sweep and has no seam.
                    RingArc(progress: progress)
                        .stroke(
                            LinearGradient(colors: [Self.amber, Self.ember], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                        )
                        .shadow(color: Self.ember.opacity(complete ? 0.8 : 0.3), radius: complete ? 16 : 6)
                    SweepHead(progress: progress, top: Self.amber, bottom: Self.ember, size: Self.lineWidth)
                    DumbbellShape()
                        .fill(.white)
                        .frame(width: 78, height: 39)
                }
                .frame(width: 132, height: 132)
                .scaleEffect(appeared ? 1 : 0.94)

                Text("세트 카운터")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .opacity(appeared ? 1 : 0)
        }
        .opacity(opacity)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: complete)
        .task { await run() }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("세트 카운터"))
    }

    /// About 1.35 s: fade in, a 0.7 s sweep that eases into place, a short glow, a 0.45 s fade out.
    private func run() async {
        if reduceMotion {
            appeared = true
            showGradient = true
            progress = 1
            complete = true
            try? await Task.sleep(for: .seconds(0.35))
            finish()
            return
        }
        withAnimation(.easeOut(duration: 0.3)) {
            appeared = true
            showGradient = true
        }
        // Quick start, long gentle settle, like a gauge needle coming to rest.
        withAnimation(.timingCurve(0.45, 0.05, 0.2, 1.0, duration: 0.7).delay(0.05)) { progress = 1 }
        try? await Task.sleep(for: .seconds(0.75))
        withAnimation(.easeOut(duration: 0.22)) { complete = true }
        try? await Task.sleep(for: .seconds(0.18))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let duration = 0.45
        withAnimation(.easeInOut(duration: duration)) { opacity = 0 }
        Task {
            try? await Task.sleep(for: .seconds(duration))
            onFinish()
        }
    }
}

/// The part of the ring drawn so far, clockwise from 12 o'clock.
private struct RingArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0 else { return path }
        let start = Angle.degrees(-90)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: start,
            endAngle: start + .degrees(360 * min(progress, 1)),
            clockwise: false
        )
        return path
    }
}

/// A soft bright dot on the leading edge of the sweep. It takes the ring's color at
/// its height and fades out just before the ring closes, so nothing marks the join.
private struct SweepHead: View, Animatable {
    var progress: Double
    let top: Color
    let bottom: Color
    let size: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            let angle = Angle.degrees(-90 + 360 * progress).radians
            let y = geometry.size.height / 2 + radius * sin(angle)
            let color = top.mix(with: bottom, by: y / max(geometry.size.height, 1))
            // Full strength through most of the sweep, gone by the time it closes.
            let fade = min(max((0.97 - progress) / 0.15, 0), 1)
            Circle()
                .fill(color.mix(with: .white, by: 0.35))
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.9), radius: 7)
                .position(x: geometry.size.width / 2 + radius * cos(angle), y: y)
                .opacity(progress > 0.02 ? fade : 0)
        }
    }
}

/// The icon's dumbbell: bar, inner plates, outer plates, and end caps, in the
/// icon's 1024-point design units (478 × 236 around the center).
struct DumbbellShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 478, rect.height / 236)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        func add(x: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat) {
            let frame = CGRect(
                x: center.x + (x - width / 2) * scale,
                y: center.y - height / 2 * scale,
                width: width * scale,
                height: height * scale
            )
            path.addRoundedRect(in: frame, cornerSize: CGSize(width: radius * scale, height: radius * scale))
        }
        add(x: 0, width: 300, height: 50, radius: 25)
        for sign in [-1.0, 1.0] as [CGFloat] {
            add(x: sign * 112, width: 62, height: 236, radius: 22)
            add(x: sign * 178, width: 50, height: 168, radius: 20)
            add(x: sign * 222, width: 34, height: 64, radius: 14)
        }
        return path
    }
}

#Preview {
    SplashView {}
}
