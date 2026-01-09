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

    // MARK: - Task Reminders

    /// Schedule notifications for all checklist items
    func scheduleTaskReminders(for items: [ChecklistItem]) async {
        // Cancel existing task reminders
        await cancelTaskReminders()

        guard isEnabled else { return }

        for item in items {
            await scheduleTaskReminder(for: item)
        }
    }

    /// Schedule a reminder for a specific task
    private func scheduleTaskReminder(for item: ChecklistItem) async {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Task Reminder"
        content.body = "\(item.displayTitle)"

        if let description = item.displayDescription {
            content.subtitle = description
        }

        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.sound = .default

        // Add actions
        content.userInfo = ["taskID": item.id.uuidString, "taskTitle": item.displayTitle]

        // Schedule for the task's time
        let hour = item.scheduledTime.hour ?? 9
        let minute = item.scheduledTime.minute ?? 0

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let identifier = "\(taskReminderPrefix)\(item.id.uuidString)"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Error scheduling task reminder: \(error)")
        }
    }

    /// Cancel all task reminder notifications
    func cancelTaskReminders() async {
        let pending = await notificationCenter.pendingNotificationRequests()
        let taskReminderIDs = pending.filter { $0.identifier.hasPrefix(taskReminderPrefix) }.map { $0.identifier }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: taskReminderIDs)
    }

    // MARK: - Task Completion Notifications

    /// Send notification when a task is completed
    func notifyTaskCompleted(task: ChecklistItem, pointsEarned: Int) async {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "✅ Task Completed!"
        content.body = "\(task.displayTitle) - Earned \(pointsEarned) point\(pointsEarned == 1 ? "" : "s")"
        content.categoryIdentifier = NotificationCategory.taskCompleted.rawValue
        content.sound = .default

        // Add celebratory sound for high-value tasks
        if pointsEarned >= 3 {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("success.wav"))
        }

        let identifier = "task_completed_\(task.id.uuidString)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Error sending task completed notification: \(error)")
        }
    }

    // MARK: - Score Update Notifications

    /// Send notification when daily score increases
    func notifyScoreIncrease(oldScore: Int, newScore: Int, reason: String) async {
        guard isEnabled else { return }
        guard newScore > oldScore else { return }

        let increase = newScore - oldScore

        let content = UNMutableNotificationContent()
        content.title = "📈 Score Increased!"
        content.body = "\(reason) - Your score went up by \(increase) points (now \(newScore)/100)"
        content.categoryIdentifier = NotificationCategory.scoreUpdate.rawValue
        content.sound = .default

        // Milestone achievements
        if newScore >= 90 && oldScore < 90 {
            content.title = "🏆 Elite Status Achieved!"
            content.body = "You've reached \(newScore) points! You're in the elite zone!"
        } else if newScore >= 75 && oldScore < 75 {
            content.title = "💪 Strong Day!"
            content.body = "You've reached \(newScore) points! Keep crushing it!"
        }

        let identifier = "\(scoreUpdateID)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Error sending score update notification: \(error)")
        }
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

    /// Send motivational notification based on current progress
    func sendMotivationalNotification(score: Int, tasksCompleted: Int, totalTasks: Int) async {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationCategory.milestone.rawValue
        content.sound = .default

        // Customize message based on progress
        if score >= 90 {
            content.title = "🔥 You're On Fire!"
            content.body = "Score: \(score)/100 - Elite performance today!"
        } else if score >= 75 {
            content.title = "💪 Strong Progress!"
            content.body = "Score: \(score)/100 - \(tasksCompleted)/\(totalTasks) tasks complete"
        } else if score >= 60 {
            content.title = "👍 Good Work!"
            content.body = "Score: \(score)/100 - Keep building momentum"
        } else {
            content.title = "💪 Keep Going!"
            content.body = "\(tasksCompleted)/\(totalTasks) tasks done - You've got this!"
        }

        let identifier = "motivational_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Error sending motivational notification: \(error)")
        }
    }

    // MARK: - Utility

    /// Get all pending notifications (for debugging/settings)
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }

    /// Cancel all notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }

    /// Update badge number
    func updateBadge(count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
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
