//
//  FinalPushLoader.swift
//  Dialed
//
//  Where final push meets the rest of the app: one calorie target every
//  screen reads, and the 8 AM notifications (the day it starts, then a
//  daily countdown).
//

import Foundation
import UserNotifications

/// Today's calorie target: your usual one, or final push's tighter one.
@MainActor
enum CalorieTarget {
    static func base(settings: UserSettings, weight: Double) -> Double {
        settings.calorieTarget ?? HomeViewModel.estimatedCutCalories(weight: weight)
    }

    static func current(settings: UserSettings, weight: Double, now: Date = Date()) -> Double {
        FinalPushStore.activeTarget(now: now) ?? base(settings: settings, weight: weight)
    }
}

enum FinalPushNotifications {
    private static let prefix = "final_push_"

    /// Rebuild the start-day note and the daily countdown up to the end day.
    static func reschedule(challenge: WeightChallenge?, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard let challenge, now < challenge.endDate else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        let friend = challenge.friendDisplayName

        // The day it starts — always, once.
        if let start = FinalPush.startMorning(end: challenge.endDate, calendar: calendar), start > now {
            let content = UNMutableNotificationContent()
            content.title = "Final push starts today 🔥"
            content.body = "14 days to beat \(friend). Your target tightens up and every day counts."
            content.sound = .default
            content.userInfo = [ReminderRoute.userInfoKey: ReminderRoute.challenge.rawValue]
            await add(center, id: "\(prefix)start", content: content, at: start, calendar: calendar)
        }

        // Then 8 AM every day until the end.
        guard FinalPushStore.dailyCountdown else { return }
        for offset in 0..<FinalPush.windowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: challenge.endDate)),
                  let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day),
                  morning > now else { continue }
            let left = FinalPush.daysLeft(end: challenge.endDate, now: morning, calendar: calendar)
            // Day 14 already has its own note.
            guard left < FinalPush.windowDays else { continue }
            let phase = FinalPush.phase(daysLeft: left)
            let content = UNMutableNotificationContent()
            content.title = phase.title
            content.body = "\(phase.line) Check in and see your target vs \(friend)."
            content.sound = .default
            content.userInfo = [ReminderRoute.userInfoKey: ReminderRoute.challenge.rawValue]
            await add(center, id: "\(prefix)\(FinalPush.key(day, calendar: calendar))", content: content, at: morning, calendar: calendar)
        }
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, content: UNNotificationContent,
                            at date: Date, calendar: Calendar) async {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(request)
    }
}
