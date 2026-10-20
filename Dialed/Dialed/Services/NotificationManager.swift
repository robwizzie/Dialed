//
//  NotificationManager.swift
//  Dialed
//
//  Comprehensive notification system for task reminders, completions, and score updates
//

import Foundation
import UserNotifications
import SwiftUI

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isEnabled: Bool = false

    private let notificationCenter = UNUserNotificationCenter.current()

    // Notification categories
    enum NotificationCategory: String {
        case taskReminder = "TASK_REMINDER"
        case taskCompleted = "TASK_COMPLETED"
        case scoreUpdate = "SCORE_UPDATE"
        case dailySummary = "DAILY_SUMMARY"
        case milestone = "MILESTONE"
    }

    // Notification identifiers
    private let taskReminderPrefix = "task_reminder_"
    private let scoreUpdateID = "score_update"
    private let dailySummaryID = "daily_summary"

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            await checkAuthorizationStatus()
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isEnabled = settings.authorizationStatus == .authorized
    }

    /// Register notification categories with actions
    func registerCategories() async {
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE",
            title: "Mark Done",
            options: [.foreground]
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Remind in 15m",
            options: []
        )

        let takePhotoAction = UNNotificationAction(
            identifier: "TAKE_PHOTO",
            title: "Take Photo",
            options: [.foreground]
        )

        let laterAction = UNNotificationAction(
            identifier: "LATER",
            title: "Later",
            options: []
        )

        // Dialed 2.0 — PlanBlock actions
        let planDone = UNNotificationAction(
            identifier: "PLAN_DONE",
            title: "Mark done",
            options: []
        )
        let planSnooze = UNNotificationAction(
            identifier: "PLAN_SNOOZE",
            title: "Snooze 10m",
            options: []
        )
        let planSkip = UNNotificationAction(
            identifier: "PLAN_SKIP",
            title: "Skip",
            options: [.destructive]
        )

        let taskReminderCategory = UNNotificationCategory(
            identifier: NotificationCategory.taskReminder.rawValue,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        let workoutPhotoCategory = UNNotificationCategory(
            identifier: "WORKOUT_PHOTO_REMINDER",
            actions: [takePhotoAction, laterAction],
            intentIdentifiers: [],
            options: []
        )

        let planBlockCategory = UNNotificationCategory(
            identifier: PlanNotificationScheduler.categoryID,
            actions: [planDone, planSnooze, planSkip],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([
            taskReminderCategory,
            workoutPhotoCategory,
            planBlockCategory
        ])
    }

    // MARK: - Task Reminders

    /// Cancel all task reminder notifications
    func cancelTaskReminders() async {
        let pending = await notificationCenter.pendingNotificationRequests()
        let taskReminderIDs = pending.filter { $0.identifier.hasPrefix(taskReminderPrefix) }.map { $0.identifier }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: taskReminderIDs)
    }

    // MARK: - Daily Summary

    /// Schedule daily summary notification (usually in the evening)
    func scheduleDailySummary(at hour: Int = 20, minute: Int = 0) async {
        guard isEnabled else { return }

        // Cancel existing daily summary
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [dailySummaryID])

        let content = UNMutableNotificationContent()
        content.title = "📊 Daily Summary"
        content.body = "Tap to review your progress and finalize your score"
        content.categoryIdentifier = NotificationCategory.dailySummary.rawValue
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: dailySummaryID, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Error scheduling daily summary: \(error)")
        }
    }

    // MARK: - Workout Photo Reminder

    /// Send notification prompting user to add a progress photo after workout
    func sendWorkoutPhotoReminder() async {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "📸 Great Workout!"
        content.body = "Add a progress photo to track your journey"
        content.categoryIdentifier = "WORKOUT_PHOTO_REMINDER"
        content.sound = .default

        // Immediate delivery
        let request = UNNotificationRequest(
            identifier: "workout_photo_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Error sending workout photo reminder: \(error)")
        }
    }

}

// MARK: - Notification Settings Model

struct NotificationSettings: Codable {
    var taskRemindersEnabled: Bool = true
    var completionNotificationsEnabled: Bool = true
    var scoreUpdatesEnabled: Bool = true
    var dailySummaryEnabled: Bool = true
    var motivationalNotificationsEnabled: Bool = true

    var dailySummaryHour: Int = 20
    var dailySummaryMinute: Int = 0

    static func load() -> NotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: "notificationSettings"),
              let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) else {
            return NotificationSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "notificationSettings")
        }
    }
}
