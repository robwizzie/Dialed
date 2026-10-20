//
//  EventModeStore.swift
//  Dialed
//
//  Event mode's saved bits: which phase the saved GoalEvent puts today in,
//  waist measurements, the suit-fitting date (with a reminder the day
//  before), and today's look-your-best check-offs.
//

import Foundation
import UserNotifications

enum EventModeStore {

    /// The saved event and where today sits relative to it, unless it's
    /// over (or not set).
    static func current(now: Date = Date(), calendar: Calendar = .current) -> (event: GoalEvent, phase: EventMode.Phase)? {
        guard let event = GoalEvent.load() else { return nil }
        let phase = EventMode.phase(event: event.date, now: now, calendar: calendar)
        return phase == .none ? nil : (event, phase)
    }

    /// The big day: no nudges, no tracking pressure.
    static func isEventDay(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        EventMode.isEventDay(event: GoalEvent.load()?.date, on: date, calendar: calendar)
    }

    // MARK: - Waist

    struct Waist: Codable, Equatable {
        var date: Date
        var inches: Double
    }

    private static let waistKey = "event.waist"

    static var waist: [Waist] {
        guard let data = UserDefaults.standard.data(forKey: waistKey),
              let list = try? JSONDecoder().decode([Waist].self, from: data) else { return [] }
        return list.sorted { $0.date < $1.date }
    }

    static func logWaist(_ inches: Double, on date: Date = Date()) {
        let calendar = Calendar.current
        var list = waist.filter { !calendar.isDate($0.date, inSameDayAs: date) }
        list.append(Waist(date: date, inches: inches))
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: waistKey) }
    }

    // MARK: - Suit fitting

    private static let fittingKey = "event.fittingDate"
    private static let fittingID = "event_fitting_reminder"

    static var fittingDate: Date? {
        UserDefaults.standard.object(forKey: fittingKey) as? Date
    }

    /// Saves the fitting date and reminds you at 9 AM the day before
    /// (nil clears both).
    static func setFitting(_ date: Date?, eventName: String) {
        UserDefaults.standard.set(date, forKey: fittingKey)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [fittingID])
        let calendar = Calendar.current
        guard let date,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)),
              let at = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore),
              at > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = EventMode.isWedding(eventName) ? "Suit fitting tomorrow 🤵" : "Fitting tomorrow"
        content.body = "At \(date.formatted(date: .omitted, time: .shortened)). Log your waist tonight so you know where you stand."
        content.sound = .default
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        center.add(UNNotificationRequest(identifier: fittingID, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    // MARK: - Today's check-offs

    private static func checksKey(_ date: Date) -> String {
        "event.checks.\(WakeSchedule.key(date))"
    }

    static func checks(on date: Date = Date()) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: checksKey(date)) ?? [])
    }

    static func toggle(_ id: String, on date: Date = Date()) {
        var set = checks(on: date)
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        UserDefaults.standard.set(Array(set).sorted(), forKey: checksKey(date))
    }
}
