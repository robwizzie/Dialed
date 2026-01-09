//
//  SettingsView.swift
//  Dialed
//
//  Settings and preferences
//

import SwiftUI

struct SettingsView: View {
    @State private var settings = UserSettings.load()
    @State private var healthKitConnected = false

    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section {
                    NavigationLink(destination: ProfileSettingsView()) {
                        SettingsRow(
                            icon: "person.fill",
                            iconGradient: [.blue, .cyan],
                            title: "Profile",
                            subtitle: "\(Int(settings.currentWeight))lbs → \(Int(settings.goalWeight))lbs"
                        )
                    }
                } header: {
                    Text("Personal")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )

                // Daily Routine Section
                Section {
                    NavigationLink(destination: TargetsSettingsView()) {
                        SettingsRow(
                            icon: "target",
                            iconGradient: [.green, .mint],
                            title: "Daily Targets",
                            subtitle: "\(Int(settings.proteinTargetGrams))g protein, \(Int(settings.waterTargetOz))oz water"
                        )
                    }

                    NavigationLink(destination: ManageDailyRoutineView()) {
                        SettingsRow(
                            icon: "checkmark.circle.fill",
                            iconGradient: [.orange, .red],
                            title: "Manage Routine",
                            subtitle: "Customize your daily tasks"
                        )
                    }
                } header: {
                    Text("Daily Routine")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )

                // Integrations Section
                Section {
                    NavigationLink(destination: NotificationsSettingsView()) {
                        SettingsRow(
                            icon: "bell.fill",
                            iconGradient: [.purple, .pink],
                            title: "Notifications",
                            subtitle: settings.notificationsEnabled ? "Enabled" : "Disabled"
                        )
                    }

                    NavigationLink(destination: HealthKitSettingsView()) {
                        SettingsRow(
                            icon: "heart.text.square.fill",
                            iconGradient: [.red, .pink],
                            title: "Apple Health",
                            subtitle: healthKitConnected ? "Connected" : "Not connected"
                        )
                    }
                } header: {
                    Text("Integrations")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )

                // App Info Section
                Section {
                    HStack {
                        Text("Version")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
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
            .navigationTitle("Settings")
            .onAppear {
                refreshSettings()
            }
        }
    }

    private func refreshSettings() {
        settings = UserSettings.load()
        healthKitConnected = HealthKitManager.shared.checkAuthorizationStatus()
    }
}

struct SettingsRow: View {
    let icon: String
    let iconGradient: [Color]
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(
                    LinearGradient(
                        colors: iconGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
    }
}

#Preview {
    SettingsView()
}
