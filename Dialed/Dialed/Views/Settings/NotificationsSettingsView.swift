//
//  NotificationsSettingsView.swift
//  Dialed
//
//  Manage notification permissions and preferences
//

import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var settings = UserSettings.load()
    @State private var notificationsEnabled: Bool
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isCheckingStatus = true

    init() {
        let settings = UserSettings.load()
        _notificationsEnabled = State(initialValue: settings.notificationsEnabled)
    }

    var body: some View {
        List {
            // Status Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification Status")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusIcon
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

            // Settings Section
            if authorizationStatus == .authorized || authorizationStatus == .provisional {
                Section {
                    Toggle("Daily Reminders", isOn: $notificationsEnabled)
                        .tint(AppColors.primary)

                    if notificationsEnabled {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.green, .mint],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Reminders enabled for selected checklist items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Get reminders for your daily routine tasks at their scheduled times.")
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

            // Actions Section
            Section {
                if authorizationStatus == .denied {
                    Button(action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Open Settings")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if authorizationStatus == .notDetermined {
                    Button(action: requestPermission) {
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Enable Notifications")
                                .foregroundStyle(.primary)
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

            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Timely Reminders")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text("Get notified at your scheduled times")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Never Miss a Task")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text("Stay consistent with your routine")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maintain Streaks")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text("Keep your momentum going")
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
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    saveChanges()
                    dismiss()
                }
            }
        }
        .task {
            await checkAuthorizationStatus()
        }
    }

    private var statusText: String {
        switch authorizationStatus {
        case .authorized, .provisional:
            return notificationsEnabled ? "Enabled" : "Disabled in app"
        case .denied:
            return "Denied - Enable in iOS Settings"
        case .notDetermined:
            return "Not configured"
        @unknown default:
            return "Unknown"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch authorizationStatus {
        case .authorized, .provisional:
            if notificationsEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success)
            } else {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(.secondary)
            }
        case .denied:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.warning)
        case .notDetermined:
            Image(systemName: "bell.badge")
                .foregroundStyle(.secondary)
        @unknown default:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            authorizationStatus = settings.authorizationStatus
            isCheckingStatus = false
        }
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Task {
                await checkAuthorizationStatus()
                if granted {
                    await MainActor.run {
                        notificationsEnabled = true
                    }
                }
            }
        }
    }

    private func saveChanges() {
        var updatedSettings = settings
        updatedSettings.notificationsEnabled = notificationsEnabled
        updatedSettings.save()
    }
}

#Preview {
    NavigationStack {
        NotificationsSettingsView()
    }
}
