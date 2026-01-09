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
                        .foregroundStyle(.primary)

                    HStack {
                        TextField("190", value: $currentWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                            .focused($focusedField, equals: .weight)

                        Text("lbs")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 50)
                    }
                }

                // Height
                VStack(alignment: .leading, spacing: 8) {
                    Text("Height")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack {
                        TextField("72", value: $height, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                            .focused($focusedField, equals: .height)

                        Text("in")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 50)
                    }
                }

                // Goal Weight
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal Weight")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack {
                        TextField("185", value: $goalWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                            .focused($focusedField, equals: .goal)

                        Text("lbs")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 50)
                    }
                }

                // Helper text
                if goalWeight > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("We'll calculate \(Int(goalWeight * 0.85))g daily protein from your goal weight")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isValid ? AppColors.primary : AppColors.primary.opacity(0.5))
                                .shadow(color: isValid ? AppColors.primary.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                        )
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
