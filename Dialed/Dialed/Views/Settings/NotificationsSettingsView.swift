//
//  NotificationsSettingsView.swift
//  Dialed
//
//  Comprehensive notification settings and preferences
//

import SwiftUI

struct NotificationsSettingsView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var settings = NotificationSettings.load()
    @State private var showPermissionAlert = false

    var body: some View {
        List {
            // Authorization status
            Section {
                HStack {
                    Image(systemName: notificationManager.isEnabled ? "bell.badge.fill" : "bell.slash.fill")
                        .foregroundStyle(notificationManager.isEnabled ? .green : .orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications")
                            .font(.body)
                            .foregroundStyle(.primary)

                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !notificationManager.isEnabled {
                        Button("Enable") {
                            Task {
                                let granted = await notificationManager.requestAuthorization()
                                if !granted {
                                    showPermissionAlert = true
                                }
                            }
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("System")
            } footer: {
                if !notificationManager.isEnabled {
                    Text("Allow notifications to receive reminders for tasks, completion confirmations, and score updates")
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )

            if notificationManager.isEnabled {
                // Task Reminders
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.taskRemindersEnabled },
                        set: { newValue in
                            settings.taskRemindersEnabled = newValue
                            settings.save()
                            Task {
                                if !newValue {
                                    await notificationManager.cancelTaskReminders()
                                }
                            }
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .red],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Task Reminders")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text("Get notified at scheduled times for each task")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Receive notifications at the scheduled time for each routine task")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )

                // Completion & Progress
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.completionNotificationsEnabled },
                        set: { newValue in
                            settings.completionNotificationsEnabled = newValue
                            settings.save()
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.green, .mint],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Task Completions")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text("Celebrate when you complete tasks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { settings.scoreUpdatesEnabled },
                        set: { newValue in
                            settings.scoreUpdatesEnabled = newValue
                            settings.save()
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Score Updates")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text("Track your daily score increases")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { settings.motivationalNotificationsEnabled },
                        set: { newValue in
                            settings.motivationalNotificationsEnabled = newValue
                            settings.save()
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .yellow],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Motivational Messages")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text("Get encouragement based on your progress")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Progress & Motivation")
                } footer: {
                    Text("Receive positive reinforcement as you make progress throughout the day")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )

                // Daily Summary
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.dailySummaryEnabled },
                        set: { newValue in
                            settings.dailySummaryEnabled = newValue
                            settings.save()
                            Task {
                                if newValue {
                                    await notificationManager.scheduleDailySummary(
                                        at: settings.dailySummaryHour,
                                        minute: settings.dailySummaryMinute
                                    )
                                }
                            }
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.pie.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Daily Summary")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text("Review your day's progress")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if settings.dailySummaryEnabled {
                        HStack {
                            Text("Summary Time")
                                .foregroundStyle(.primary)

                            Spacer()

                            HStack(spacing: 4) {
                                Picker("Hour", selection: Binding(
                                    get: { settings.dailySummaryHour },
                                    set: { newValue in
                                        settings.dailySummaryHour = newValue
                                        settings.save()
                                        Task {
                                            await notificationManager.scheduleDailySummary(
                                                at: newValue,
                                                minute: settings.dailySummaryMinute
                                            )
                                        }
                                    }
                                )) {
                                    ForEach(0..<24) { hour in
                                        Text(String(format: "%02d", hour)).tag(hour)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: 60)
                                .clipped()

                                Text(":")

                                Picker("Minute", selection: Binding(
                                    get: { settings.dailySummaryMinute },
                                    set: { newValue in
                                        settings.dailySummaryMinute = newValue
                                        settings.save()
                                        Task {
                                            await notificationManager.scheduleDailySummary(
                                                at: settings.dailySummaryHour,
                                                minute: newValue
                                            )
                                        }
                                    }
                                )) {
                                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                                        Text(String(format: "%02d", minute)).tag(minute)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: 60)
                                .clipped()
                            }
                            .frame(height: 100)
                        }
                    }
                } header: {
                    Text("Daily Summary")
                } footer: {
                    if settings.dailySummaryEnabled {
                        Text("Get a notification at \(String(format: "%02d:%02d", settings.dailySummaryHour, settings.dailySummaryMinute)) to review your day")
                    } else {
                        Text("Get a daily reminder to review your progress and finalize your score")
                    }
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
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Notification Permission Denied", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable notifications in Settings to receive reminders and updates")
        }
        .onAppear {
            Task {
                await notificationManager.checkAuthorizationStatus()
            }
        }
    }

    private var statusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized:
            return "Enabled"
        case .denied:
            return "Denied - Open Settings to enable"
        case .notDetermined:
            return "Not set up"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
}

#Preview {
    NavigationStack {
        NotificationsSettingsView()
    }
}
