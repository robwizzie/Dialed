//
//  OnboardingFlowView.swift
//  Dialed
//
//  Onboarding flow container with navigation
//

import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        Group {
            switch viewModel.currentStep {
            case .welcome:
                WelcomeView(onContinue: {
                    withAnimation {
                        viewModel.moveToNext()
                    }
                })

            case .profile:
                ProfileSetupView(
                    currentWeight: $viewModel.currentWeight,
                    height: $viewModel.height,
                    goalWeight: $viewModel.goalWeight,
                    onContinue: {
                        withAnimation {
                            viewModel.moveToNext()
                        }
                    },
                    onBack: {
                        withAnimation {
                            viewModel.moveToPrevious()
                        }
                    }
                )

            case .targets:
                TargetsSetupView(
                    proteinTarget: $viewModel.proteinTarget,
                    waterTarget: $viewModel.waterTarget,
                    calorieTarget: $viewModel.calorieTarget,
                    workoutsPerWeek: $viewModel.workoutsPerWeek,
                    onContinue: {
                        withAnimation {
                            viewModel.moveToNext()
                        }
                    },
                    onBack: {
                        withAnimation {
                            viewModel.moveToPrevious()
                        }
                    }
                )

            case .permissions:
                PermissionsView(
                    onContinue: {
                        viewModel.completeOnboarding()
                        appState.completeOnboarding()
                    },
                    onBack: {
                        withAnimation {
                            viewModel.moveToPrevious()
                        }
                    }
                )
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
    }
}

// MARK: - ViewModel

class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome

    // Profile data
    @Published var currentWeight: Double = 190
    @Published var height: Double = 72  // inches
    @Published var goalWeight: Double = 185

    // Targets (auto-calculated from profile)
    @Published var proteinTarget: Double = 0
    @Published var waterTarget: Double = 0
    @Published var calorieTarget: Double?
    @Published var workoutsPerWeek: Int = 6

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case profile = 1
        case targets = 2
        case permissions = 3
    }

    init() {
        // Auto-calculate initial targets
        updateTargets()
    }

    func moveToNext() {
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }

        // Update targets when leaving profile screen
        if currentStep == .profile {
            updateTargets()
        }

        currentStep = nextStep
    }

    func moveToPrevious() {
        guard let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prevStep
    }

    func completeOnboarding() {
        // Save settings
        let settings = UserSettings(
            currentWeight: currentWeight,
            height: height,
            goalWeight: goalWeight,
            proteinTargetGrams: proteinTarget,
            waterTargetOz: waterTarget,
            calorieTarget: calorieTarget,
            expectedWorkoutsPerWeek: workoutsPerWeek,
            notificationsEnabled: true,
            enabledNotifications: Set(Constants.ChecklistType.allCases.map { $0.rawValue }),
            healthKitEnabled: HealthKitManager.shared.checkAuthorizationStatus(),
            customChecklistTimes: nil
        )

        settings.save()
    }

    private func updateTargets() {
        // Auto-calculate protein (0.85g per lb of goal weight)
        proteinTarget = UserSettings.calculateProteinTarget(goalWeight: goalWeight)

        // Auto-calculate water (half body weight in oz)
        waterTarget = UserSettings.calculateWaterTarget(currentWeight: currentWeight)
    }
}

#Preview {
    OnboardingFlowView()
        .environmentObject(AppState())
}
