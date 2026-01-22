//
//  HealthKitSettingsView.swift
//  Dialed
//
//  Manage HealthKit permissions and sync status
//

import SwiftUI

struct HealthKitSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var settings = UserSettings.load()
    @State private var isAuthorized = false
    @State private var isRequesting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPermissionDeniedAlert = false

    var body: some View {
        List {
            // Status Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connection Status")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Text(isAuthorized ? "Connected to Apple Health" : "Not connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isAuthorized {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.success)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)
                    }
                }
            } header: {
                Text("Status")
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )

            // Data Access Section
            Section {
                DataAccessRow(
                    icon: "bed.double.fill",
                    title: "Sleep Data",
                    description: "Duration, stages, and quality metrics",
                    isEnabled: isAuthorized
                )

                DataAccessRow(
                    icon: "figure.walk",
                    title: "Workouts & Activity",
                    description: "Workout detection and step count",
                    isEnabled: isAuthorized
                )

                DataAccessRow(
                    icon: "drop.fill",
                    title: "Water Intake",
                    description: "Daily hydration tracking",
                    isEnabled: isAuthorized
                )

                DataAccessRow(
                    icon: "heart.fill",
                    title: "Heart Metrics",
                    description: "HRV and resting heart rate",
                    isEnabled: isAuthorized
                )
            } header: {
                Text("Data Access")
            } footer: {
                Text("Dialed reads health data to automatically track your fitness metrics. Your data stays on your device.")
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )

            // Actions Section
            Section {
                if !isAuthorized {
                    Button(action: requestHealthKitPermissions) {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "heart.text.square")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Text("Connect to Apple Health")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .disabled(isRequesting)
                    
                    Button(action: { showPermissionDeniedAlert = true }) {
                        HStack {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.secondary)
                            Text("Reset Health Permissions")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(AppColors.danger)
                    }
                } else {
                    Button(action: {
                        if let url = URL(string: "x-apple-health://") {
                            openURL(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "heart.text.square")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Open Apple Health")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Actions")
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )

            // Privacy Section
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(AppColors.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privacy First")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text("Your health data stays on your device")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Tracking")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text("No manual logging required")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Real-time Sync")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text("Data updates automatically")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Benefits")
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            print("👀 [HealthKitSettings] View appeared, checking authorization status...")
            checkAuthorizationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            print("👀 [HealthKitSettings] App entered foreground, rechecking authorization...")
            checkAuthorizationStatus()
        }
        .alert("Reset Health Permissions", isPresented: $showPermissionDeniedAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("If you previously denied Health access, you need to enable it in iOS Settings:\n\n1. Open Settings app\n2. Scroll to 'Dialed'\n3. Tap 'Health'\n4. Enable 'Sleep Analysis' and other data types\n5. Return to Dialed and check connection status")
        }
    }

    private func checkAuthorizationStatus() {
        let status = HealthKitManager.shared.checkAuthorizationStatus()
        print("👀 [HealthKitSettings] Authorization status check: \(status)")
        
        // For READ permissions, we need to try reading data to verify
        Task {
            let actualAccess = await HealthKitManager.shared.verifyDataAccess()
            await MainActor.run {
                print("👀 [HealthKitSettings] Actual data access verified: \(actualAccess)")
                isAuthorized = actualAccess
                
                // Update settings
                var updatedSettings = settings
                updatedSettings.healthKitEnabled = actualAccess
                updatedSettings.save()
                settings = UserSettings.load()
                
                if actualAccess {
                    print("✅ [HealthKitSettings] Connected to Apple Health!")
                } else {
                    print("❌ [HealthKitSettings] Cannot read health data")
                }
            }
        }
    }

    private func requestHealthKitPermissions() {
        print("🔄 [HealthKitSettings] User tapped Connect button")
        isRequesting = true
        showError = false

        Task {
            do {
                try await HealthKitManager.shared.requestAuthorization()
                print("✅ [HealthKitSettings] Authorization request completed")
                
                // Wait for HealthKit to fully update
                print("⏳ [HealthKitSettings] Waiting for permissions to sync...")
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                
                await MainActor.run {
                    // Recheck actual status
                    checkAuthorizationStatus()
                    isRequesting = false
                    
                    let statusDesc = HealthKitManager.shared.getAuthorizationStatusDescription()
                    print("✅ [HealthKitSettings] Final status: \(statusDesc)")
                    
                    if statusDesc == "denied" {
                        print("⚠️ [HealthKitSettings] Permission was denied - showing alert")
                        showPermissionDeniedAlert = true
                    } else if !isAuthorized {
                        showError = true
                        errorMessage = "Please allow access when the Health permission dialog appears. Tap 'Allow' to grant access."
                    }
                }
            } catch {
                print("❌ [HealthKitSettings] Authorization failed: \(error.localizedDescription)")
                await MainActor.run {
                    isRequesting = false
                    showError = true
                    errorMessage = "Could not connect to Health. Make sure Health access is enabled in iOS Settings."
                }
            }
        }
    }
}

struct DataAccessRow: View {
    let icon: String
    let title: String
    let description: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(
                    isEnabled ?
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    LinearGradient(
                        colors: [.secondary.opacity(0.5), .secondary.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary.opacity(0.3))
            }
        }
    }
}

#Preview {
    NavigationStack {
        HealthKitSettingsView()
    }
}
