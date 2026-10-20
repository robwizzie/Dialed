//
//  SplashScreenView.swift
//  Dialed
//
//  Launch moment in the Neka style: the Dialed mark "dials in" — the
//  scale's ticks light up as the gradient arc fills and the glass knob's
//  pointer turns with it, then clicks into place — while the wordmark
//  and a personal line rise in, and the splash lifts away to reveal Home.
//
//  The app is built *underneath* from the first frame, so Home starts
//  loading your data while the splash plays instead of after it. The
//  whole thing takes ~1.5s (instant with Reduce Motion), and only a few
//  shapes animate — no blurs.
//

import SwiftUI
import SwiftData

struct SplashScreenView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress: CGFloat = 0
    @State private var showWordmark = false
    @State private var showLine = false
    @State private var settled = false
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
            // Skincare / face-wash tasks were dropped; clear any saved ones once.
            SkincareCleanup.runIfNeeded(context: modelContext)
        }
    }

    // MARK: - Splash

    private var splash: some View {
        ZStack {
            background

            VStack(spacing: 34) {
                Spacer()
                dial
                    .frame(width: 212, height: 212)
                VStack(spacing: 10) {
                    (Text("Dialed").foregroundColor(Neka.ink) + Text(".").foregroundColor(Neka.green))
                        .font(Neka.display(46, weight: .bold))
                        .tracking(-1.2)
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

    /// The Dialed mark, turning from empty to "dialed in". Same drawing as
    /// the app icon; it gives a small click of a bounce when it lands.
    private var dial: some View {
        DialedMark(value: 0.74 * Double(progress))
            .scaleEffect(settled ? 1 : 0.965)
    }

    // MARK: - Choreography

    private func run() {
        if reduceMotion {
            progress = 1
            showWordmark = true
            showLine = true
            settled = true
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { settled = true }
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

#Preview {
    SplashScreenView()
        .environmentObject(AppState())
        .modelContainer(for: DialedSchema.allModels, inMemory: true)
}
