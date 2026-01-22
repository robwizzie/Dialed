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

            case .checklist:
                ChecklistSetupView(
                    selectedItems: $viewModel.selectedChecklistItems,
                    customTimes: $viewModel.customChecklistTimes,
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

            case .notifications:
                NotificationsView(
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

    // Checklist setup
    @Published var selectedChecklistItems: Set<Constants.ChecklistType> = [
        .amSkincare,
        .lunchVitamins,
        .creatine,
        .pmSkincare
    ]
    @Published var customChecklistTimes: [Constants.ChecklistType: (hour: Int, minute: Int)] = [
        .amSkincare: (7, 0),
        .lunchVitamins: (12, 0),
        .creatine: (16, 0),
        .pmSkincare: (21, 0)
    ]

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case profile = 1
        case targets = 2
        case checklist = 3
        case permissions = 4
        case notifications = 5
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
        // Convert checklist times to UserSettings format
        var customTimes: [String: ScheduledTime] = [:]
        for (type, time) in customChecklistTimes {
            customTimes[type.rawValue] = ScheduledTime(hour: time.hour, minute: time.minute)
        }

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
            enabledNotifications: Set(selectedChecklistItems.map { $0.rawValue }),
            healthKitEnabled: HealthKitManager.shared.checkAuthorizationStatus(),
            customChecklistTimes: customTimes.isEmpty ? nil : customTimes
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
