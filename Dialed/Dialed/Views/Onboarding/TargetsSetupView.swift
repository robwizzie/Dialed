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
            headerSection
            
            ScrollView {
                VStack(spacing: 24) {
                    proteinSection
                    waterSection
                    caloriesSection
                    workoutFrequencySection
                }
                .padding(.horizontal, 30)
            }

            Spacer()
            
            navigationButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .onTapGesture {
            focusedField = nil
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
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
    }
    
    private var proteinSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Protein")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("Auto-calculated")
                                .font(.caption)
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(AppColors.primary.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .stroke(AppColors.primary.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }

                        HStack {
                            TextField("190", value: $proteinTarget, format: .number)
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
                                .focused($focusedField, equals: .protein)

                            Text("g/day")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 70)
                        }

            Text("Target: 0.8-1g per lb of goal weight")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Water")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("Auto-calculated")
                                .font(.caption)
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(AppColors.primary.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .stroke(AppColors.primary.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }

                        HStack {
                            TextField("120", value: $waterTarget, format: .number)
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
                                .focused($focusedField, equals: .water)

                            Text("oz/day")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 70)
                        }

            Text("Target: Half your body weight in oz")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var caloriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Calories")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("Optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.secondary.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .stroke(.secondary.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }

                        HStack {
                            TextField("Optional", value: $calorieTarget, format: .number)
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
                                .focused($focusedField, equals: .calories)

                            Text("cal/day")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 70)
                        }

            Text("Leave blank to skip calorie tracking")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var workoutFrequencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
                        Text("Expected Workouts")
                            .font(.headline)
                            .foregroundStyle(.primary)

            HStack(spacing: 12) {
                ForEach(3...7, id: \.self) { days in
                    Button(action: {
                        workoutsPerWeek = days
                    }) {
                        Text("\(days)")
                            .font(.title3.bold())
                            .foregroundColor(workoutsPerWeek == days ? .white : .primary)
                            .frame(width: 50, height: 50)
                            .background(
                                Group {
                                    if workoutsPerWeek == days {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(AppColors.primary)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.ultraThinMaterial)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(workoutsPerWeek == days ? .clear : .white.opacity(0.1), lineWidth: 0.5)
                                )
                                .shadow(color: workoutsPerWeek == days ? AppColors.primary.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                            )
                    }
                }
            }

            Text("days per week")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var navigationButtons: some View {
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
