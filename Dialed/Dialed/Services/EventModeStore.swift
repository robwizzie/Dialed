//
//  EventModeStore.swift
//  Dialed
//
//  Event mode's saved bits: which phase the saved GoalEvent puts today in
//  and today's look-your-best check-offs.
//

import Foundation
import UserNotifications

enum EventModeStore {

    /// The saved event and where today sits relative to it, unless it's
    /// over (or not set).
    static func current(now: Date = Date(), calendar: Calendar = .current) -> (event: GoalEvent, phase: EventMode.Phase)? {
        retireCountdownOnce()
        guard let event = GoalEvent.load() else { return nil }
        let phase = EventMode.phase(event: event.date, now: now, calendar: calendar)
        return phase == .none ? nil : (event, phase)
    }

    /// The big day: no nudges, no tracking pressure.
    static func isEventDay(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        EventMode.isEventDay(event: GoalEvent.load()?.date, on: date, calendar: calendar)
    }

    // MARK: - Retired countdown

    /// The suit-fit countdown (waist log and fitting reminder) is gone:
    /// once, clear what it saved and any reminder still pending.
    static func retireCountdownOnce(_ defaults: UserDefaults = .standard) {
        let flag = "event.countdownRetired.v1"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        defaults.removeObject(forKey: "event.waist")
        defaults.removeObject(forKey: "event.fittingDate")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["event_fitting_reminder"])
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
