//
//  ProfileSetupView.swift
//  Dialed
//
//  Collect user's current stats and goals
//

import SwiftUI

struct ProfileSetupView: View {
    @Binding var currentWeight: Double
    @Binding var height: Double
    @Binding var goalWeight: Double

    let onContinue: () -> Void
    let onBack: () -> Void

    @FocusState private var focusedField: Field?

    enum Field {
        case weight, height, goal
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Your Profile")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text("We'll use this to calculate your personalized targets")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Input fields
            VStack(spacing: 24) {
                // Current Weight
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Weight")
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)

                    HStack {
                        TextField("190", value: $currentWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .padding()
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .focused($focusedField, equals: .weight)

                        Text("lbs")
                            .font(.title3)
                            .foregroundColor(AppColors.textSecondary)
                            .frame(width: 50)
                    }
                }

                // Height
                VStack(alignment: .leading, spacing: 8) {
                    Text("Height")
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)

                    HStack {
                        TextField("72", value: $height, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .padding()
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .focused($focusedField, equals: .height)

                        Text("in")
                            .font(.title3)
                            .foregroundColor(AppColors.textSecondary)
                            .frame(width: 50)
                    }
                }

                // Goal Weight
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal Weight")
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)

                    HStack {
                        TextField("185", value: $goalWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .padding()
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .focused($focusedField, equals: .goal)

                        Text("lbs")
                            .font(.title3)
                            .foregroundColor(AppColors.textSecondary)
                            .frame(width: 50)
                    }
                }

                // Helper text
                if goalWeight > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppColors.primary)

                        Text("We'll calculate \(Int(goalWeight * 0.85))g daily protein from your goal weight")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 30)

            Spacer()

            // Navigation buttons
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.headline)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.surface)
                    .cornerRadius(12)
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isValid ? AppColors.primary : AppColors.primary.opacity(0.5))
                        .cornerRadius(12)
                }
                .disabled(!isValid)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .onTapGesture {
            focusedField = nil
        }
    }

    private var isValid: Bool {
        currentWeight > 0 && height > 0 && goalWeight > 0
    }
}

#Preview {
    ProfileSetupView(
        currentWeight: .constant(190),
        height: .constant(72),
        goalWeight: .constant(185),
        onContinue: {},
        onBack: {}
    )
}
