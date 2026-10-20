//
//  WakeSuggestionEngine.swift
//  Dialed
//
//  Reads your calendar against your wake-up schedule and suggests a
//  different time when a day calls for it:
//    • something early ("Dentist 8:15 AM") → get up early enough for it,
//      leaving time to get ready (and drive there);
//    • a day off work ("PTO", a holiday, a workday with nothing from
//      work on it) with a free morning → sleep in a bit, up to 90 min.
//  You accept or ignore each one; nothing changes on its own. Also merges
//  Apple Calendar and Google Calendar events so a meeting synced to both
//  shows once. Pure Foundation, tested.
//

import Foundation

/// One calendar event, from Apple Calendar (EventKit) or Google Calendar.
struct PlannedEvent: Codable, Equatable, Identifiable {
    enum Source: String, Codable { case apple, google }

    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    var calendarTitle: String
    /// "#RRGGBB" from the calendar.
    var colorHex: String?
    var location: String?
    var notes: String?
    var source: Source

    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// What counts, what means work, and how much time mornings need.
struct CalendarPrefs: Codable, Equatable {
    /// Calendars to read; nil = all of them.
    var enabledCalendarIDs: Set<String>?
    /// Calendars that are work (a shift calendar, a work account).
    var workCalendarIDs: Set<String> = []
    /// Event titles that mean work.
    var workKeywords: [String] = ["work", "shift", "office", "clinic", "on call", "on-call"]
    /// All-day titles that mean a day off.
    var offKeywords: [String] = ["pto", "vacation", "day off", "off work", "holiday", "ooo", "out of office", "sick day", "leave"]
    /// Your usual workdays (1 = Sunday … 7 = Saturday).
    var workDays: Set<Int> = [2, 3, 4, 5, 6]
    /// From waking up to walking out the door.
    var prepMinutes = 60
    /// Drive / commute to a morning commitment.
    var commuteMinutes = 0
    /// Most a day off pushes the alarm back.
    var sleepInMinutes = 90
    /// 8 PM heads-up when tomorrow has a suggestion.
    var eveningReminder = true

    private static let key = "calendar.prefs"
    static let didChange = Notification.Name("CalendarPrefsDidChange")

    static func load(_ defaults: UserDefaults = .standard) -> CalendarPrefs {
        guard let data = defaults.data(forKey: key),
              let p = try? JSONDecoder().decode(CalendarPrefs.self, from: data) else { return CalendarPrefs() }
        return p
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func includes(_ calendarID: String) -> Bool {
        enabledCalendarIDs?.contains(calendarID) ?? true
    }
}

enum WakeSuggestionEngine {

    struct Suggestion: Equatable, Identifiable {
        enum Kind: String { case earlier, later }

        let date: Date
        /// Scheduled wake (minutes after midnight), nil on a sleep-in day.
        let current: Int?
        let suggested: Int
        let kind: Kind
        /// "Dentist at 8:15 AM — an hour to get ready."
        let reason: String
        /// The event that prompted it, for "earlier".
        let eventTitle: String?
        let eventStart: Date?

        /// Changes when the suggestion does, so ignoring 7:00 doesn't hide a later 6:30.
        var id: String { "\(WakeSchedule.key(date))-\(suggested)" }
    }

    /// Morning commitments start before noon (and after 4 AM — a red-eye
    /// at 2 AM is a different problem).
    static let morningRange = (4 * 60)..<(12 * 60)
    /// Never suggest getting up before this.
    static let earliestWake = 4 * 60
    /// Small differences aren't worth a change.
    static let minimumChange = 10

    /// Major holidays a "Holidays" calendar's all-day event means a day off for.
    static let daysOff = ["new year", "martin luther king", "presidents", "memorial day", "juneteenth",
                          "independence day", "labor day", "thanksgiving", "christmas"]

    /// Suggestions for `days` days from `from`'s date, skipping days you've
    /// already changed by hand and suggestions you've ignored.
    static func suggestions(schedule: WakeSchedule, events: [PlannedEvent], prefs: CalendarPrefs,
                            from: Date, days: Int = 14, dismissed: Set<String> = [],
                            calendar: Calendar = .current) -> [Suggestion] {
        let start = calendar.startOfDay(for: from)
        let relevant = events.filter { prefs.includes($0.calendarID) }
        let work = workPattern(relevant, prefs: prefs, calendar: calendar)
        var out: [Suggestion] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            guard !schedule.isChanged(on: day, calendar: calendar) else { continue }
            let dayEvents = relevant.filter { occurs($0, on: day, calendar: calendar) }
            guard let s = suggestion(for: day, scheduled: schedule.minutes(on: day, calendar: calendar),
                                     events: dayEvents, prefs: prefs, work: work, calendar: calendar),
                  !dismissed.contains(s.id) else { continue }
            // Today's suggestion only matters before the time it's for.
            if offset == 0, let wake = calendar.date(bySettingHour: s.suggested / 60, minute: s.suggested % 60, second: 0, of: day),
               wake <= from { continue }
            out.append(s)
        }
        return out
    }

    /// One day's suggestion, or nil when the schedule already fits.
    static func suggestion(for day: Date, scheduled: Int?, events: [PlannedEvent], prefs: CalendarPrefs,
                           work: WorkPattern = WorkPattern(), calendar: Calendar = .current) -> Suggestion? {
        let dayStart = calendar.startOfDay(for: day)
        let lead = prefs.prepMinutes + prefs.commuteMinutes

        // 1. Something early: up in time to get ready and get there.
        let morning = events
            .filter { !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: dayStart) }
            .filter { morningRange.contains(minuteOfDay($0.start, calendar: calendar)) }
            .sorted { $0.start < $1.start }
        if let first = morning.first {
            let startMinute = minuteOfDay(first.start, calendar: calendar)
            let needed = max(earliestWake, roundDown(startMinute - lead))
            if scheduled.map({ needed <= $0 - minimumChange }) ?? true {
                let time = WakeSchedule.clock(startMinute)
                let ready = lead >= 60 && lead % 60 == 0 ? "\(lead / 60) h" : "\(lead) min"
                let reason = "\(first.title) at \(time), \(ready) to get ready" + (prefs.commuteMinutes > 0 ? " and get there." : ".")
                return Suggestion(date: dayStart, current: scheduled, suggested: needed, kind: .earlier,
                                  reason: reason, eventTitle: first.title, eventStart: first.start)
            }
            return nil
        }

        // 2. A day off with a free morning: sleep in a little.
        guard let scheduled, let why = offReason(day: dayStart, events: events, prefs: prefs,
                                                 work: work, calendar: calendar) else { return nil }
        let later = min(scheduled + prefs.sleepInMinutes, 11 * 60)
        guard later >= scheduled + minimumChange else { return nil }
        return Suggestion(date: dayStart, current: scheduled, suggested: later, kind: .later,
                          reason: why, eventTitle: nil, eventStart: nil)
    }

    // MARK: - Work and days off

    static func isWork(_ e: PlannedEvent, prefs: CalendarPrefs) -> Bool {
        if prefs.workCalendarIDs.contains(e.calendarID) { return true }
        let t = e.title.lowercased()
        return prefs.workKeywords.contains { !$0.isEmpty && containsWord(t, $0.lowercased()) }
    }

    /// When your calendar tracks work: the weekdays it shows you working
    /// and the span it covers. Only with work on at least 3 different days,
    /// so one stray meeting doesn't turn every other weekday into a "day
    /// off" — and only inside the span, since a calendar that starts
    /// showing shifts next Monday says nothing about this week.
    struct WorkPattern: Equatable {
        var weekdays: Set<Int> = []
        var span: ClosedRange<Date>?

        func expectsWork(on day: Date, calendar: Calendar = .current) -> Bool {
            guard let span, span.contains(calendar.startOfDay(for: day)) else { return false }
            return weekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    static func workPattern(_ events: [PlannedEvent], prefs: CalendarPrefs, calendar: Calendar = .current) -> WorkPattern {
        let workDays = Set(events.filter { isWork($0, prefs: prefs) }.map { calendar.startOfDay(for: $0.start) })
        guard workDays.count >= 3, let first = workDays.min(), let last = workDays.max() else { return WorkPattern() }
        return WorkPattern(weekdays: Set(workDays.map { calendar.component(.weekday, from: $0) }).intersection(prefs.workDays),
                           span: first...last)
    }

    /// Why a day reads as a day off, or nil when it doesn't.
    static func offReason(day: Date, events: [PlannedEvent], prefs: CalendarPrefs,
                          work: WorkPattern = WorkPattern(), calendar: Calendar = .current) -> String? {
        for e in events where e.isAllDay {
            let t = e.title.lowercased()
            if prefs.offKeywords.contains(where: { !$0.isEmpty && containsWord(t, $0.lowercased()) }) {
                return "\(e.title): a day off, so sleep in a little."
            }
            if e.calendarTitle.lowercased().contains("holiday"), daysOff.contains(where: { t.contains($0) }) {
                return "\(e.title): no work, so sleep in a little."
            }
        }
        if work.expectsWork(on: day, calendar: calendar), !events.contains(where: { isWork($0, prefs: prefs) }) {
            return "Nothing from work on your calendar, so sleep in a little."
        }
        return nil
    }

    // MARK: - Merging Apple and Google

    /// The same event synced to both calendars shows once: same title
    /// (ignoring case) starting within 5 minutes. Apple's copy wins.
    static func merge(_ lists: [PlannedEvent]...) -> [PlannedEvent] {
        var out: [PlannedEvent] = []
        for e in lists.flatMap({ $0 }).sorted(by: { ($0.source == .apple ? 0 : 1) < ($1.source == .apple ? 0 : 1) }) {
            let duplicate = out.contains {
                $0.title.trimmingCharacters(in: .whitespaces).lowercased() == e.title.trimmingCharacters(in: .whitespaces).lowercased()
                    && abs($0.start.timeIntervalSince(e.start)) <= 5 * 60 && $0.isAllDay == e.isAllDay
            }
            if !duplicate { out.append(e) }
        }
        return out.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    // MARK: - Helpers

    static func occurs(_ e: PlannedEvent, on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        if e.isAllDay { return e.start < end && e.end > start }
        return e.start >= start && e.start < end
    }

    static func minuteOfDay(_ d: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Down to the nearest 5 minutes.
    static func roundDown(_ minutes: Int) -> Int { minutes - ((minutes % 5) + 5) % 5 }

    /// "pto" in "PTO – beach" but not "office" in "postoffice run".
    static func containsWord(_ text: String, _ word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: word, range: searchRange) {
            let beforeOK = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if beforeOK && afterOK { return true }
            searchRange = r.upperBound..<text.endIndex
        }
        return false
    }
}
