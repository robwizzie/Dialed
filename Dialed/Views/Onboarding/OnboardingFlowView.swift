//
//  OnboardingFlowView.swift
//  Dialed
//
//  Onboarding flow container
//

import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 30) {
            Text("Welcome to Dialed")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(AppColors.primary)

            Text("Your automated fitness OS")
                .font(.title2)
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            Button(action: {
                // For now, skip onboarding
                appState.completeOnboarding()
            }) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppColors.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
    }
}

#Preview {
    OnboardingFlowView()
        .environmentObject(AppState())
}
