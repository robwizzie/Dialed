//
//  WakeSchedule.swift
//  Dialed
//
//  When you get up: a usual time for each weekday (or none, to sleep in),
//  plus one-off changes for specific dates ("Thursday's flight, up at
//  4:30"). From it come tonight's bedtime (wake − sleep goal), a wind-down
//  nudge, a good-morning note, and the day planner's wake anchor. Pure
//  Foundation and tested; notifications are below.
//

import Foundation
import UserNotifications

struct WakeSchedule: Codable, Equatable {
    /// Weekday (1 = Sunday … 7 = Saturday) → minutes after midnight.
    /// Missing = no set wake time that day.
    var weekly: [Int: Int]
    /// "yyyy-MM-dd" → minutes after midnight, or `Self.off` for no wake time.
    var overrides: [String: Int] = [:]
    var sleepGoalMinutes = 480
    var windDownMinutes = 30
    var bedtimeReminder = true
    var morningNote = true

    static let off = -1

    static let standard = WakeSchedule(weekly: [2: 390, 3: 390, 4: 390, 5: 390, 6: 390, 7: 480, 1: 480])

    // MARK: - Reading

    func minutes(on date: Date, calendar: Calendar = .current) -> Int? {
        if let o = overrides[Self.key(date, calendar: calendar)] { return o == Self.off ? nil : o }
        return weekly[calendar.component(.weekday, from: date)]
    }

    func wake(on date: Date, calendar: Calendar = .current) -> Date? {
        guard let m = minutes(on: date, calendar: calendar) else { return nil }
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: calendar.startOfDay(for: date))
    }

    /// Bed by this to get your sleep goal before `date`'s wake time
    /// (lands the evening before).
    func bedtime(before date: Date, calendar: Calendar = .current) -> Date? {
        wake(on: date, calendar: calendar).map { $0.addingTimeInterval(-Double(sleepGoalMinutes) * 60) }
    }

    func isChanged(on date: Date, calendar: Calendar = .current) -> Bool {
        overrides[Self.key(date, calendar: calendar)] != nil
    }

    // MARK: - Editing

    mutating func setUsual(_ minutes: Int?, weekday: Int) {
        weekly[weekday] = minutes
    }

    /// Change just one date (`nil` = no wake time that day).
    mutating func setDay(_ minutes: Int?, on date: Date, calendar: Calendar = .current) {
        let usual = weekly[calendar.component(.weekday, from: date)]
        let key = Self.key(date, calendar: calendar)
        // Setting it back to the usual time just clears the change.
        if minutes == usual { overrides[key] = nil } else { overrides[key] = minutes ?? Self.off }
    }

    mutating func resetDay(_ date: Date, calendar: Calendar = .current) {
        overrides[Self.key(date, calendar: calendar)] = nil
    }

    /// Forget changes for days that have passed.
    mutating func prune(before date: Date, calendar: Calendar = .current) {
        let today = Self.key(date, calendar: calendar)
        overrides = overrides.filter { $0.key >= today }
    }

    // MARK: - Formatting

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 390 → "6:30 AM"
    static func clock(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):" + String(format: "%02d", m) + (h < 12 ? " AM" : " PM")
    }

    /// 480 → "8 h", 450 → "7 h 30 m"
    static func duration(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) m"
    }

    // MARK: - Storage

    private static let storeKey = "wake.schedule"

    static func load() -> WakeSchedule {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let s = try? JSONDecoder().decode(WakeSchedule.self, from: data) else { return .standard }
        return s
    }

    func save() {
        var copy = self
        copy.prune(before: Date())
        if let data = try? JSONEncoder().encode(copy) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
        NotificationCenter.default.post(name: .wakeScheduleDidChange, object: nil)
        Task { await WakeNotifications.reschedule() }
    }
}

extension Notification.Name {
    static let wakeScheduleDidChange = Notification.Name("wakeScheduleDidChange")
}

// MARK: - Notifications

/// Wind-down and good-morning notes for the next week, rebuilt whenever
/// the schedule changes and on launch.
enum WakeNotifications {
    private static let prefix = "wake_sched_"

    static func reschedule(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let schedule = WakeSchedule.load()
        let calendar = Calendar.current
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let wake = schedule.wake(on: day, calendar: calendar) else { continue }
            let key = WakeSchedule.key(day, calendar: calendar)
            let wakeText = wake.formatted(date: .omitted, time: .shortened)

            if schedule.bedtimeReminder, let bed = schedule.bedtime(before: day, calendar: calendar) {
                let nudge = bed.addingTimeInterval(-Double(schedule.windDownMinutes) * 60)
                if nudge > now {
                    let content = UNMutableNotificationContent()
                    content.title = "Wind down 🌙"
                    content.body = "Up at \(wakeText) tomorrow. Lights out by \(bed.formatted(date: .omitted, time: .shortened)) "
                        + "for \(WakeSchedule.duration(schedule.sleepGoalMinutes)) of sleep."
                    content.sound = .default
                    await add(center, id: "\(prefix)bed_\(key)", content: content, at: nudge, calendar: calendar)
                }
            }
            if schedule.morningNote, wake > now {
                let content = UNMutableNotificationContent()
                content.title = "Good morning ☀️"
                content.body = "Your sleep score and today's plan are ready. Start with a glass of water."
                content.sound = .default
                content.userInfo = ["link": "home"]
                await add(center, id: "\(prefix)wake_\(key)", content: content, at: wake.addingTimeInterval(5 * 60), calendar: calendar)
            }
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
