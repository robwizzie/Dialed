//
//  TargetsSettingsView.swift
//  Dialed
//
//  Edit daily targets (protein, water, calories, workouts) after onboarding
//

import SwiftUI

struct TargetsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = UserSettings.load()

    @State private var proteinTarget: Double
    @State private var waterTarget: Double
    @State private var calorieTarget: Double?
    @State private var workoutsPerWeek: Int

    @FocusState private var focusedField: Field?

    enum Field {
        case protein, water, calories
    }

    init() {
        let settings = UserSettings.load()
        _proteinTarget = State(initialValue: settings.proteinTargetGrams)
        _waterTarget = State(initialValue: settings.waterTargetOz)
        _calorieTarget = State(initialValue: settings.calorieTarget)
        _workoutsPerWeek = State(initialValue: settings.expectedWorkoutsPerWeek)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                proteinSection
                waterSection
                caloriesSection
                workoutFrequencySection
            }
            .padding()
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Targets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onTapGesture {
            focusedField = nil
        }
    }
    
    // MARK: - Sections
    
    private var proteinSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Protein")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("Recommended: \(Int(settings.goalWeight * 0.85))g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                        Text("Recommended: \(Int(settings.currentWeight / 2))oz")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

            HStack(spacing: 12) {
                if calorieTarget != nil {
                    Button(action: {
                        calorieTarget = nil
                    }) {
                        Text("Remove calorie tracking")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.red.opacity(0.15))
                                    .overlay(
                                        Capsule()
                                            .stroke(.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                } else {
                    Text("Leave blank to skip calorie tracking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

    private var isValid: Bool {
        proteinTarget > 0 && waterTarget > 0 && workoutsPerWeek > 0
    }

    private func saveChanges() {
        var updatedSettings = settings
        updatedSettings.proteinTargetGrams = proteinTarget
        updatedSettings.waterTargetOz = waterTarget
        updatedSettings.calorieTarget = calorieTarget
        updatedSettings.expectedWorkoutsPerWeek = workoutsPerWeek
        updatedSettings.save()
    }
}

#Preview {
    NavigationStack {
        TargetsSettingsView()
    }
}
