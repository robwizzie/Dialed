//
//  PermissionsView.swift
//  Dialed
//
//  Request HealthKit permissions with clear benefits
//

import SwiftUI

struct PermissionsView: View {
    @State private var isRequestingPermissions = false
    @State private var permissionGranted = false
    @State private var showError = false
    @State private var errorMessage = ""

    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 60))
                    .foregroundColor(AppColors.primary)
                    .padding(.bottom, 16)

                Text("Connect to Apple Health")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text("Dialed works best with automated data from your devices")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // What we'll read
            VStack(alignment: .leading, spacing: 20) {
                Text("What we'll access:")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 30)

                VStack(spacing: 16) {
                    PermissionRow(
                        icon: "bed.double.fill",
                        title: "Sleep Data",
                        description: "Auto-score sleep from RingConn metrics"
                    )

                    PermissionRow(
                        icon: "figure.walk",
                        title: "Workouts & Activity",
                        description: "Detect workouts and mile runs automatically"
                    )

                    PermissionRow(
                        icon: "drop.fill",
                        title: "Water Intake",
                        description: "Sync from your smart water bottle"
                    )

                    PermissionRow(
                        icon: "heart.fill",
                        title: "Heart Metrics",
                        description: "HRV and resting HR for recovery insights"
                    )
                }
                .padding(.horizontal, 30)
            }

            Spacer()

            // Privacy note
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(AppColors.success)

                    Text("Your health data stays on your device")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                if showError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(AppColors.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
            }
            .padding(.bottom, 16)

            // Navigation buttons
            VStack(spacing: 12) {
                Button(action: requestHealthKitPermissions) {
                    HStack {
                        if isRequestingPermissions {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(permissionGranted ? "✓ Connected" : "Enable Health Access")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(permissionGranted ? AppColors.success : AppColors.primary)
                    .cornerRadius(12)
                }
                .disabled(isRequestingPermissions || permissionGranted)

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
                        Text(permissionGranted ? "Continue" : "Skip for Now")
                            .font(.headline)
                            .foregroundColor(permissionGranted ? .white : AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(permissionGranted ? AppColors.primary : AppColors.surface)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
    }

    private func requestHealthKitPermissions() {
        isRequestingPermissions = true
        showError = false

        Task {
            do {
                try await HealthKitManager.shared.requestAuthorization()
                await MainActor.run {
                    permissionGranted = true
                    isRequestingPermissions = false
                }
            } catch {
                await MainActor.run {
                    isRequestingPermissions = false
                    showError = true
                    errorMessage = "Could not connect to Health. You can enable this later in Settings."
                }
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(AppColors.primary)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
    }
}

#Preview {
    PermissionsView(onContinue: {}, onBack: {})
}
