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

            // The Dialed mark — same dial as the app icon.
            DialedMark()
                .frame(width: 148, height: 148)
                .motionTilt()
                .padding(.bottom, 32)

            (Text("Dialed").foregroundColor(Neka.ink) + Text(".").foregroundColor(Neka.green))
                .font(Neka.display(56, weight: .bold))
                .tracking(-1.5)

            // Tagline
            Text("Your Automated Fitness OS")
                .font(.title3)
                .foregroundStyle(.secondary)
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
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppColors.primary)
                            .shadow(color: AppColors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                    )
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
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
