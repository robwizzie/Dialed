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

            // App icon with liquid glass effect
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.primary.opacity(0.3), AppColors.primary.opacity(0)],
                            center: .center,
                            startRadius: 50,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 10)

                // Glass container
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .shadow(color: AppColors.primary.opacity(0.2), radius: 20, x: 0, y: 10)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.05), .white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 8
                    )
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                AppColors.primary.opacity(0.8),
                                AppColors.primary,
                                AppColors.primary.opacity(0.9),
                                AppColors.primary
                            ]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: AppColors.primary.opacity(0.5), radius: 8, x: 0, y: 0)

                Text("100")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .primary.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.bottom, 40)

            // App name
            Text("Dialed")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

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
