//
//  TargetsSetupView.swift
//  Dialed
//
//  Set daily targets (auto-calculated from profile with overrides)
//

import SwiftUI

struct TargetsSetupView: View {
    @Binding var proteinTarget: Double
    @Binding var waterTarget: Double
    @Binding var calorieTarget: Double?
    @Binding var workoutsPerWeek: Int

    let onContinue: () -> Void
    let onBack: () -> Void

    @FocusState private var focusedField: Field?

    enum Field {
        case protein, water, calories
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Daily Targets")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text("We've calculated these based on your goals. Adjust if needed.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            ScrollView {
                VStack(spacing: 24) {
                    // Protein
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Protein")
                                .font(.headline)
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("Auto-calculated")
                                .font(.caption)
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.primary.opacity(0.2))
                                .cornerRadius(6)
                        }

                        HStack {
                            TextField("190", value: $proteinTarget, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(AppColors.textPrimary)
                                .padding()
                                .background(AppColors.surface)
                                .cornerRadius(12)
                                .focused($focusedField, equals: .protein)

                            Text("g/day")
                                .font(.title3)
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: 70)
                        }

                        Text("Target: 0.8-1g per lb of goal weight")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    // Water
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Water")
                                .font(.headline)
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("Auto-calculated")
                                .font(.caption)
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.primary.opacity(0.2))
                                .cornerRadius(6)
                        }

                        HStack {
                            TextField("120", value: $waterTarget, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(AppColors.textPrimary)
                                .padding()
                                .background(AppColors.surface)
                                .cornerRadius(12)
                                .focused($focusedField, equals: .water)

                            Text("oz/day")
                                .font(.title3)
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: 70)
                        }

                        Text("Target: Half your body weight in oz")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    // Calories (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Calories")
                                .font(.headline)
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("Optional")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.textSecondary.opacity(0.2))
                                .cornerRadius(6)
                        }

                        HStack {
                            TextField("Optional", value: $calorieTarget, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(AppColors.textPrimary)
                                .padding()
                                .background(AppColors.surface)
                                .cornerRadius(12)
                                .focused($focusedField, equals: .calories)

                            Text("cal/day")
                                .font(.title3)
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: 70)
                        }

                        Text("Leave blank to skip calorie tracking")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    // Workout frequency
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expected Workouts")
                            .font(.headline)
                            .foregroundColor(AppColors.textPrimary)

                        HStack(spacing: 12) {
                            ForEach(3...7, id: \.self) { days in
                                Button(action: {
                                    workoutsPerWeek = days
                                }) {
                                    Text("\(days)")
                                        .font(.title3.bold())
                                        .foregroundColor(workoutsPerWeek == days ? .white : AppColors.textPrimary)
                                        .frame(width: 50, height: 50)
                                        .background(workoutsPerWeek == days ? AppColors.primary : AppColors.surface)
                                        .cornerRadius(12)
                                }
                            }
                        }

                        Text("days per week")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, 30)
            }

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
        proteinTarget > 0 && waterTarget > 0 && workoutsPerWeek > 0
    }
}

#Preview {
    TargetsSetupView(
        proteinTarget: .constant(190),
        waterTarget: .constant(120),
        calorieTarget: .constant(nil),
        workoutsPerWeek: .constant(6),
        onContinue: {},
        onBack: {}
    )
}
