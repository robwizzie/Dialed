//
//  WelcomeView.swift
//  Dialed
//
//  First screen of onboarding flow
//

import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon placeholder (animated ring)
            ZStack {
                Circle()
                    .stroke(AppColors.primary.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(AppColors.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                Text("100")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primary)
            }
            .padding(.bottom, 40)

            // App name
            Text("Dialed")
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(AppColors.textPrimary)

            // Tagline
            Text("Your Automated Fitness OS")
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
                .padding(.top, 8)

            Spacer()

            // Features
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "bed.double.fill",
                    title: "Auto Sleep Scoring",
                    description: "RingConn data analyzed automatically"
                )

                FeatureRow(
                    icon: "figure.strengthtraining.traditional",
                    title: "Smart Workout Detection",
                    description: "Apple Watch workouts tracked instantly"
                )

                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Daily Score & Streaks",
                    description: "One number, complete picture"
                )
            }
            .padding(.horizontal, 30)

            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(AppColors.primary)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
