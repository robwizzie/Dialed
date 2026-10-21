//
//  MonthlyPhotoReminder.swift
//  Dialed
//
//  "📸 Progress photo day": the same day every month (the day of your
//  first photo unless you pick another, kept to 1–28 so short months
//  never skip it), at a time you choose. Settings and the date math are
//  pure and tested; the notification is scheduled below.
//

import Foundation
import UserNotifications

struct MonthlyPhotoReminder: Codable, Equatable {
    var enabled = false
    /// Day of the month, 1–28.
    var day = 1
    var hour = 9
    var minute = 0

    static let notificationID = "progressPhoto.monthly"
    private static let storageKey = "progressPhoto.monthlyReminder"
    /// Set when the reminder is tapped; the photos screen opens the camera.
    static let openCameraKey = "progressPhoto.openCamera"

    /// The first photo's day of the month, kept to 1–28.
    static func defaultDay(firstPhoto: Date?, calendar: Calendar = .current) -> Int {
        guard let firstPhoto else { return 1 }
        return clampDay(calendar.component(.day, from: firstPhoto))
    }

    static func clampDay(_ day: Int) -> Int { min(28, max(1, day)) }

    /// The next reminder at or after `now`.
    func next(after now: Date, calendar: Calendar = .current) -> Date? {
        let day = Self.clampDay(self.day)
        var c = calendar.dateComponents([.year, .month], from: now)
        c.day = day
        c.hour = hour
        c.minute = minute
        guard let thisMonth = calendar.date(from: c) else { return nil }
        if thisMonth >= now { return thisMonth }
        return calendar.date(byAdding: .month, value: 1, to: thisMonth)
    }

    /// Whether `date` is photo day.
    func isPhotoDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        enabled && calendar.component(.day, from: date) == Self.clampDay(day)
    }

    // MARK: - Storage

    static var isSaved: Bool { UserDefaults.standard.data(forKey: storageKey) != nil }

    static func load(firstPhoto: Date? = nil) -> MonthlyPhotoReminder {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(MonthlyPhotoReminder.self, from: data) {
            return saved
        }
        return MonthlyPhotoReminder(day: defaultDay(firstPhoto: firstPhoto))
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
        Task { await schedule() }
    }

    // MARK: - Notification

    /// One repeating calendar notification, replaced whenever settings change.
    func schedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard enabled else { return }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let content = UNMutableNotificationContent()
        content.title = "📸 Progress photo day"
        content.body = "Same spot, same light, same pose. Last month's photo is waiting as a ghost to line up with."
        content.sound = .default
        content.userInfo = [ReminderRoute.userInfoKey: ReminderRoute.progressPhoto.rawValue]
        var when = DateComponents()
        when.day = Self.clampDay(day)
        when.hour = hour
        when.minute = minute
        try? await center.add(UNNotificationRequest(
            identifier: Self.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }
}
