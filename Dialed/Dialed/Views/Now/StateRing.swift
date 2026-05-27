//
//  StateRing.swift
//  Dialed
//
//  The hero ring component used across the "Now" home screen. Each ring is
//  one of the four state pillars (Recovery / Readiness / Energy / Strain).
//
//  Design notes — what makes this feel premium:
//    1. Two-stop angular gradient stroke (not flat color)
//    2. Inactive track in pillar color at 12% — keeps cohesion even at 0
//    3. Subtle pulsing outer glow when the score is healthy (≥ good)
//    4. Numbers count up alongside the ring drawing in (spring animation)
//    5. Large headline number with monospaced digits — no jitter on tick
//    6. Optional confidence shimmer at the bottom for low-confidence data
//

import SwiftUI

struct StateRing: View {
    let pillar: AppColors.Pillar
    let score: Int             // 0–100
    let grade: StateEngine.ScoreBreakdown.Grade
    let confidence: Double     // 0–1; below 0.5 shows a "data thin" hint

    /// Optional override sizing. Default is the home-screen size.
    var diameter: CGFloat = 140
    var lineWidth: CGFloat = 12

    @State private var animatedProgress: Double = 0
    @State private var animatedScore: Double = 0
    @State private var pulse: Bool = false

    private var progress: Double { Double(score) / 100.0 }
    private var isHealthy: Bool {
        grade == .excellent || grade == .good
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Outer breathing glow — only when healthy.
                if isHealthy {
                    Circle()
                        .fill(pillar.glowColor)
                        .frame(width: diameter + 30, height: diameter + 30)
                        .blur(radius: 28)
                        .opacity(pulse ? 0.28 : 0.14)
                        .animation(
                            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                            value: pulse
                        )
                }

                // Inactive track
                Circle()
                    .stroke(pillar.trackColor, lineWidth: lineWidth)
                    .frame(width: diameter, height: diameter)

                // Active stroke with angular gradient — Apple Fitness-style depth.
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: pillar.gradient),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(-90))
                    .shadow(
                        color: pillar.gradient.last!.opacity(0.45),
                        radius: 8, x: 0, y: 0
                    )

                // Center content
                VStack(spacing: 2) {
                    Image(systemName: pillar.systemIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: pillar.gradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("\(Int(animatedScore))")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .contentTransition(.numericText())

                    Text(pillar.displayName.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .frame(width: diameter + 30, height: diameter + 30)
            .contentShape(Rectangle())

            // Grade pill (under the ring)
            HStack(spacing: 6) {
                if confidence < 0.5 {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                Text(grade.displayLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(pillar.gradient.last!.opacity(0.15))
            )
            .overlay(
                Capsule().stroke(pillar.gradient.last!.opacity(0.35), lineWidth: 0.6)
            )
        }
        .onAppear { animateIn() }
        .onChange(of: score) { _, _ in animateIn() }
    }

    private func animateIn() {
        withAnimation(.spring(response: 1.2, dampingFraction: 0.85)) {
            animatedProgress = progress
            animatedScore = Double(score)
        }
        if isHealthy { pulse = true }
    }
}

// MARK: - Compact variant used in the strip header

struct CompactStateRing: View {
    let pillar: AppColors.Pillar
    let score: Int
    var diameter: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .stroke(pillar.trackColor, lineWidth: 4)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: Double(score) / 100.0)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: pillar.gradient),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)

            Text("\(score)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
    }
}

#Preview("Rings grid") {
    ZStack {
        AppColors.nowBackground.ignoresSafeArea()
        VStack(spacing: 20) {
            HStack(spacing: 24) {
                StateRing(pillar: .recovery, score: 78, grade: .good, confidence: 0.9)
                StateRing(pillar: .readiness, score: 82, grade: .good, confidence: 0.9)
            }
            HStack(spacing: 24) {
                StateRing(pillar: .energy, score: 65, grade: .fair, confidence: 0.7)
                StateRing(pillar: .strain, score: 34, grade: .poor, confidence: 0.95)
            }
        }
    }
    .preferredColorScheme(.dark)
}
