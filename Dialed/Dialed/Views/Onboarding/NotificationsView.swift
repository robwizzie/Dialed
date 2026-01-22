//
//  NotificationsView.swift
//  Dialed
//
//  Request notification permissions and configure preferences
//

import SwiftUI
import UserNotifications

struct NotificationsView: View {
    @State private var isRequestingPermissions = false
    @State private var permissionGranted = false
    @State private var permissionDenied = false

    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.bottom, 16)

                Text("Stay on Track")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Get gentle reminders for your daily routine tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Benefits
            VStack(alignment: .leading, spacing: 20) {
                Text("Notification benefits:")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 30)

                VStack(spacing: 16) {
                    NotificationBenefitRow(
                        icon: "clock.fill",
                        title: "Timely Reminders",
                        description: "Stay consistent with your routine"
                    )

                    NotificationBenefitRow(
                        icon: "checkmark.seal.fill",
                        title: "Never Miss a Task",
                        description: "Get notified for uncompleted items"
                    )

                    NotificationBenefitRow(
                        icon: "flame.fill",
                        title: "Maintain Your Streak",
                        description: "Keep your momentum going daily"
                    )

                    NotificationBenefitRow(
                        icon: "moon.zzz.fill",
                        title: "Sleep Reminders",
                        description: "Wind-down alerts for better rest"
                    )
                }
                .padding(.horizontal, 30)
            }

            Spacer()

            // Status message
            if permissionDenied {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)

                        Text("Notifications are disabled")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    Text("You can enable them later in iOS Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 16)
            } else if permissionGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.success)

                    Text("Notifications enabled")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)
            }

            // Navigation buttons
            VStack(spacing: 12) {
                if !permissionGranted && !permissionDenied {
                    Button(action: requestNotificationPermissions) {
                        HStack {
                            if isRequestingPermissions {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Enable Notifications")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppColors.primary)
                                .shadow(color: AppColors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                        )
                    }
                    .disabled(isRequestingPermissions)
                }

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
                        Text(permissionGranted ? "Continue" : "Skip for Now")
                            .font(.headline)
                            .foregroundColor(permissionGranted ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Group {
                                    if permissionGranted {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(AppColors.primary)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.ultraThinMaterial)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(permissionGranted ? .clear : .white.opacity(0.1), lineWidth: 0.5)
                                )
                                .shadow(color: permissionGranted ? AppColors.primary.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                            )
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            checkCurrentPermissions()
        }
    }

    private func checkCurrentPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    permissionGranted = true
                    permissionDenied = false
                case .denied:
                    permissionGranted = false
                    permissionDenied = true
                default:
                    permissionGranted = false
                    permissionDenied = false
                }
            }
        }
    }

    private func requestNotificationPermissions() {
        isRequestingPermissions = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                isRequestingPermissions = false

                if granted {
                    permissionGranted = true
                    permissionDenied = false
                } else {
                    permissionGranted = false
                    permissionDenied = true
                }
            }
        }
    }
}

struct NotificationBenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    NotificationsView(onContinue: {}, onBack: {})
}
