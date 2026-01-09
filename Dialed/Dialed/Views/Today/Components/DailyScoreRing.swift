//
//  DailyScoreRing.swift
//  Dialed
//
//  Circular progress ring showing daily score (0-100)
//

import SwiftUI

struct DailyScoreRing: View {
    let score: Int
    let isProvisional: Bool

    @State private var animatedProgress: Double = 0

    private var progress: Double {
        Double(score) / 100.0
    }

    private var scoreColor: Color {
        AppColors.scoreColor(for: score)
    }

    private var scoreGrade: String {
        AppColors.scoreGrade(for: score)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Ring with liquid glass effect
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [scoreColor.opacity(0.3), scoreColor.opacity(0)],
                            center: .center,
                            startRadius: 70,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .blur(radius: 10)
                    .opacity(animatedProgress)

                // Glass container
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 160, height: 160)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .shadow(color: scoreColor.opacity(0.2), radius: 20, x: 0, y: 10)

                // Background ring track
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.05), .white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 14
                    )
                    .frame(width: 140, height: 140)

                // Progress ring with gradient
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                scoreColor.opacity(0.8),
                                scoreColor,
                                scoreColor.opacity(0.9),
                                scoreColor
                            ]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: scoreColor.opacity(0.5), radius: 8, x: 0, y: 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animatedProgress)

                // Inner glow on progress
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        scoreColor.opacity(0.3),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 4)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animatedProgress)

                // Score text with vibrancy
                VStack(spacing: 6) {
                    Text("\(score)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .primary.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .contentTransition(.numericText())
                        .shadow(color: scoreColor.opacity(0.3), radius: 10, x: 0, y: 5)

                    Text(scoreGrade)
                        .font(.caption.bold())
                        .foregroundColor(scoreColor)
                        .textCase(.uppercase)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(scoreColor.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(scoreColor.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
            }

            // Provisional indicator with glass pill
            if isProvisional {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Live Score")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
        }
        .onAppear {
            animatedProgress = progress
        }
        .onChange(of: score) { _, _ in
            withAnimation {
                animatedProgress = progress
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        DailyScoreRing(score: 92, isProvisional: false)
        DailyScoreRing(score: 76, isProvisional: true)
        DailyScoreRing(score: 43, isProvisional: true)
    }
    .padding()
    .background(AppColors.background)
}
