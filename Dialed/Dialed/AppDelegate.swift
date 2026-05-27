//
//  AppDelegate.swift
//  Dialed
//
//  App delegate for notification handling
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Register notification categories
        Task {
            await NotificationManager.shared.registerCategories()
        }

        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap/actions
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {

        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        // Handle different actions
        switch actionIdentifier {
        case "COMPLETE":
            // User tapped "Mark Done" on task reminder
            if let taskID = userInfo["taskID"] as? String {
                handleCompleteTask(taskID: taskID)
            }

        case "SNOOZE":
            // User tapped "Remind in 15m" on task reminder
            if let taskID = userInfo["taskID"] as? String {
                handleSnoozeTask(taskID: taskID)
            }

        case "TAKE_PHOTO":
            // User tapped "Take Photo" after workout
            handleTakePhoto()

        // Dialed 2.0 — plan block actions. We post to NotificationCenter
        // so the view model can resolve the block by ID inside its own
        // ModelContext (the app delegate has none of its own).
        case "PLAN_DONE":
            if let blockID = userInfo["planBlockID"] as? String {
                NotificationCenter.default.post(
                    name: NSNotification.Name("PlanBlockMarkDone"),
                    object: nil,
                    userInfo: ["planBlockID": blockID]
                )
            }

        case "PLAN_SNOOZE":
            if let blockID = userInfo["planBlockID"] as? String {
                NotificationCenter.default.post(
                    name: NSNotification.Name("PlanBlockSnooze"),
                    object: nil,
                    userInfo: ["planBlockID": blockID]
                )
            }

        case "PLAN_SKIP":
            if let blockID = userInfo["planBlockID"] as? String {
                NotificationCenter.default.post(
                    name: NSNotification.Name("PlanBlockSkip"),
                    object: nil,
                    userInfo: ["planBlockID": blockID]
                )
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped notification (not an action button)
            handleNotificationTap(notification: response.notification)

        default:
            break
        }

        completionHandler()
    }

    // MARK: - Action Handlers

    private func handleCompleteTask(taskID: String) {
        // Post notification to mark task complete
        NotificationCenter.default.post(
            name: NSNotification.Name("CompleteTaskFromNotification"),
            object: nil,
            userInfo: ["taskID": taskID]
        )
    }

    private func handleSnoozeTask(taskID: String) {
        // Schedule a new notification in 15 minutes
        Task {
            let content = UNMutableNotificationContent()
            content.title = "⏰ Reminder"
            content.body = "Don't forget your task!"
            content.sound = .default
            content.userInfo = ["taskID": taskID]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            let request = UNNotificationRequest(
                identifier: "snooze_\(taskID)_\(Date().timeIntervalSince1970)",
                content: content,
                trigger: trigger
            )

            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func handleTakePhoto() {
        // Post notification to open photo capture
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenPhotoCaptureFromNotification"),
            object: nil
        )
    }

    private func handleNotificationTap(notification: UNNotification) {
        let categoryIdentifier = notification.request.content.categoryIdentifier

        // Deep link based on notification type
        switch categoryIdentifier {
        case NotificationManager.NotificationCategory.taskReminder.rawValue:
            // Navigate to Today view (checklist)
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToToday"),
                object: nil
            )

        case NotificationManager.NotificationCategory.scoreUpdate.rawValue,
             NotificationManager.NotificationCategory.milestone.rawValue:
            // Navigate to Today view (score)
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToToday"),
                object: nil
            )

        case NotificationManager.NotificationCategory.dailySummary.rawValue:
            // Navigate to History view
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToHistory"),
                object: nil
            )

        case PlanNotificationScheduler.categoryID:
            // Dialed 2.0 — open the Plan tab
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToPlan"),
                object: nil
            )

        default:
            break
        }
    }
}
