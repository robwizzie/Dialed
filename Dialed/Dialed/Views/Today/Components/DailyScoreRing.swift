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
            // Ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(AppColors.surface, lineWidth: 16)
                    .frame(width: 160, height: 160)

                // Progress ring
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        scoreColor,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animatedProgress)

                // Score text
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .contentTransition(.numericText())

                    Text(scoreGrade)
                        .font(.caption.bold())
                        .foregroundColor(scoreColor)
                        .textCase(.uppercase)
                }
            }

            // Provisional indicator
            if isProvisional {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                    Text("Live Score")
                        .font(.caption)
                }
                .foregroundColor(AppColors.textSecondary)
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
