//
//  ProfileSettingsView.swift
//  Dialed
//
//  Edit profile (weight, height, goals) after onboarding
//

import SwiftUI

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = UserSettings.load()

    @State private var currentWeight: Double
    @State private var height: Double
    @State private var goalWeight: Double

    @FocusState private var focusedField: Field?

    enum Field {
        case weight, height, goal
    }

    init() {
        let settings = UserSettings.load()
        _currentWeight = State(initialValue: settings.currentWeight)
        _height = State(initialValue: settings.height)
        _goalWeight = State(initialValue: settings.goalWeight)
    }

    var body: some View {
        ScrollView {
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

                // Info box
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Impact on your targets")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                    }

                    Text("Changing your goal weight will auto-update your protein target (0.85g per lb). Water target is based on current weight (half in oz).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.blue.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .padding()
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Profile")
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

    private var isValid: Bool {
        currentWeight > 0 && height > 0 && goalWeight > 0
    }

    private func saveChanges() {
        var updatedSettings = settings
        updatedSettings.currentWeight = currentWeight
        updatedSettings.height = height
        updatedSettings.goalWeight = goalWeight

        // Auto-recalculate targets
        updatedSettings.proteinTargetGrams = UserSettings.calculateProteinTarget(goalWeight: goalWeight)
        updatedSettings.waterTargetOz = UserSettings.calculateWaterTarget(currentWeight: currentWeight)

        updatedSettings.save()
    }
}

#Preview {
    NavigationStack {
        ProfileSettingsView()
    }
}
