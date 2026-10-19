//
//  SplashScreenView.swift
//  Dialed
//
//  Launch moment in the Neka style: a dial "dials in" — tick marks sweep
//  around the ring as a gradient arc fills and the knob's indicator
//  rides its leading edge — then the wordmark and a personal line rise
//  in, and the splash lifts away to reveal Home.
//
//  The app is built *underneath* from the first frame, so Home starts
//  loading your data while the splash plays instead of after it. The
//  whole thing takes ~1.5s (instant with Reduce Motion), and only a few
//  shapes animate — no blurs.
//

import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress: CGFloat = 0
    @State private var showWordmark = false
    @State private var showLine = false
    @State private var showCheck = false
    @State private var finished = false

    private let personalLine = SplashScreenView.makePersonalLine()

    var body: some View {
        ZStack {
            ContentView()
                .environmentObject(appState)

            if !finished {
                splash
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity.combined(with: .scale(scale: 1.06))
                    ))
                    .zIndex(1)
            }
        }
        .task {
            // Run the legacy → Dialed 2.0 migration once. Cheap no-op
            // after the first launch; failure mode is "try again next launch".
            LegacyMigrationService.runIfNeeded(context: modelContext)
        }
    }

    // MARK: - Splash

    private var splash: some View {
        ZStack {
            background

            VStack(spacing: 34) {
                Spacer()
                dial
                    .frame(width: 196, height: 196)
                VStack(spacing: 10) {
                    Text("Dialed.")
                        .font(Neka.display(46, weight: .bold))
                        .tracking(-1.2)
                        .foregroundColor(Neka.ink)
                    Text("Dial in your day.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
                .opacity(showWordmark ? 1 : 0)
                .offset(y: showWordmark ? 0 : 14)

                Spacer()

                if let personalLine {
                    Text(personalLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Neka.surface))
                        .overlay(Capsule().stroke(Neka.hairline, lineWidth: 0.5))
                        .opacity(showLine ? 1 : 0)
                        .offset(y: showLine ? 0 : 10)
                        .padding(.bottom, 28)
                }
            }
            .padding(.horizontal, 24)
        }
        .onAppear(perform: run)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dialed")
    }

    private var background: some View {
        ZStack {
            Neka.paper
            RadialGradient(
                colors: [Neka.greenSoft, Neka.greenSoft.opacity(0)],
                center: UnitPoint(x: 0.85, y: 0.1), startRadius: 0, endRadius: 420
            )
            RadialGradient(
                colors: [Neka.lavenderSoft.opacity(0.9), Neka.lavenderSoft.opacity(0)],
                center: UnitPoint(x: 0.1, y: 0.95), startRadius: 0, endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Dial

    private var dial: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let ringWidth: CGFloat = 10
            let radius = size / 2 - ringWidth / 2
            // Arc runs from 7 o'clock clockwise to 5 o'clock (300°), like a knob.
            let sweep: CGFloat = 300.0 / 360.0
            let startAngle: Double = 120

            ZStack {
                // Tick ring, revealed by the same progress as the arc.
                DialTicks(count: 50, sweepFraction: sweep, startAngle: startAngle)
                    .stroke(Neka.inkTertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .padding(-14)
                    .mask(
                        Circle()
                            .trim(from: 0, to: progress * sweep)
                            .stroke(style: StrokeStyle(lineWidth: 40))
                            .rotationEffect(.degrees(startAngle))
                            .padding(-14)
                    )

                // Track
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(Neka.track, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))

                // Fill
                Circle()
                    .trim(from: 0, to: max(0.001, progress * sweep))
                    .stroke(
                        AngularGradient(
                            colors: [Neka.green, Neka.sky, Neka.lavender, Neka.orange],
                            center: .center,
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(startAngle + 300)
                        ),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(startAngle))

                // Knob
                Circle()
                    .fill(Neka.surface)
                    .frame(width: size * 0.62, height: size * 0.62)
                    .shadow(color: Neka.shadow, radius: 12, y: 6)
                    .overlay(
                        Circle().stroke(Neka.hairline, lineWidth: 0.5)
                            .frame(width: size * 0.62, height: size * 0.62)
                    )

                // Knob indicator — rides the arc's leading edge.
                Capsule()
                    .fill(Neka.ink)
                    .frame(width: 5, height: size * 0.12)
                    .offset(y: -size * 0.2)
                    .rotationEffect(.degrees(startAngle + 90 + Double(progress * sweep) * 360))
                    // Hands off to the check once the dial is in.
                    .opacity(showCheck ? 0 : 1)
                    .scaleEffect(showCheck ? 0.6 : 1)

                // Check that lands when the dial is "in".
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundColor(Neka.green)
                    .scaleEffect(showCheck ? 1 : 0.4)
                    .opacity(showCheck ? 1 : 0)

                // Leading-edge dot on the ring.
                Circle()
                    .fill(Neka.surface)
                    .frame(width: ringWidth + 6, height: ringWidth + 6)
                    .overlay(Circle().stroke(Neka.ink, lineWidth: 2.5))
                    .offset(x: radius)
                    .rotationEffect(.degrees(startAngle + Double(progress * sweep) * 360))
                    .opacity(progress > 0.02 ? 1 : 0)
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: - Choreography

    private func run() {
        if reduceMotion {
            progress = 1
            showWordmark = true
            showLine = true
            showCheck = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.25)) { finished = true }
            }
            return
        }

        withAnimation(.timingCurve(0.65, 0, 0.25, 1, duration: 0.95)) {
            progress = 1
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.35)) {
            showWordmark = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.6)) {
            showLine = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { showCheck = true }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
            withAnimation(.easeInOut(duration: 0.45)) { finished = true }
        }
    }

    // MARK: - Personal line

    /// "Day 18 vs. Jake · 13 days left", or a time-of-day greeting.
    private static func makePersonalLine(now: Date = Date()) -> String? {
        let name = (UserDefaults.standard.string(forKey: "user.firstName") ?? "")
            .trimmingCharacters(in: .whitespaces)
        if let challenge = WeightChallenge.load() {
            let cal = Calendar.current
            let start = cal.startOfDay(for: challenge.startDate)
            let end = cal.startOfDay(for: challenge.endDate)
            let today = cal.startOfDay(for: now)
            let total = max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1)
            let day = min(total, max(1, (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1))
            let left = max(0, cal.dateComponents([.day], from: today, to: end).day ?? 0)
            if today >= start && left > 0 {
                return "Day \(day) vs. \(challenge.friendDisplayName) · \(left) day\(left == 1 ? "" : "s") left"
            }
        }
        guard !name.isEmpty else { return nil }
        let hour = Calendar.current.component(.hour, from: now)
        let greeting: String
        switch hour {
        case 5..<12:  greeting = "Good morning"
        case 12..<17: greeting = "Good afternoon"
        case 17..<22: greeting = "Good evening"
        default:      greeting = "Late one"
        }
        return "\(greeting), \(name)."
    }
}

/// Evenly spaced radial ticks along an arc of the circle.
private struct DialTicks: Shape {
    let count: Int
    let sweepFraction: CGFloat
    let startAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        for i in 0...count {
            let t = Double(i) / Double(count)
            let angle = (startAngle + t * Double(sweepFraction) * 360) * .pi / 180
            let major = i % 5 == 0
            let inner = outer - (major ? 9 : 5)
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        }
        return path
    }
}

#Preview {
    SplashScreenView()
        .environmentObject(AppState())
        .modelContainer(for: DialedSchema.allModels, inMemory: true)
}
