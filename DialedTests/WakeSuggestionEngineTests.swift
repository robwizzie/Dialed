//
//  WakeSuggestionEngineTests.swift
//  DialedTests
//
//  Calendar-aware wake-up suggestions: earlier for a morning commitment,
//  later on a day off, nothing on days you changed or ignored, and one
//  copy of an event synced to both calendars.
//

import XCTest
@testable import Dialed

final class WakeSuggestionEngineTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false,
                       calendarTitle: String = "Home", source: PlannedEvent.Source = .apple) -> PlannedEvent {
        PlannedEvent(id: UUID().uuidString, title: title, start: start, end: end, isAllDay: allDay,
                     calendarID: calendarTitle, calendarTitle: calendarTitle, colorHex: nil,
                     location: nil, notes: nil, source: source)
    }

    /// 8:30 AM every day.
    private let schedule = WakeSchedule(weekly: [1: 510, 2: 510, 3: 510, 4: 510, 5: 510, 6: 510, 7: 510])
    private let now: Date = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 21))!   // Tue 9 PM
    }()

    func testEarlierForMorningEventsAndLaterOnDaysOff() {
        let events = [
            event("Dentist", at(22, 8, 15), at(22, 9)),
            event("PTO – beach", at(23, 0), at(24, 0), allDay: true),
            event("Workout", at(27, 10), at(27, 11))     // not work, not before 8:30 + an hour… but after wake
        ]
        let s = WakeSuggestionEngine.suggestions(schedule: schedule, events: events, prefs: CalendarPrefs(),
                                                 from: now, days: 8, calendar: calendar)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].kind, .earlier)
        XCTAssertEqual(s[0].suggested, 7 * 60 + 15)        // 8:15 − 1 h
        XCTAssertTrue(s[0].reason.hasPrefix("Dentist at 8:15 AM"))
        XCTAssertEqual(s[1].kind, .later)
        XCTAssertEqual(s[1].suggested, 10 * 60)            // 8:30 + 90 min
    }

    func testCommuteAndRoundingAndSleepInDays() {
        var prefs = CalendarPrefs()
        prefs.prepMinutes = 45
        prefs.commuteMinutes = 20
        var sleepIn = schedule
        sleepIn.setUsual(nil, weekday: 5)                  // Thursdays: no alarm
        let s = WakeSuggestionEngine.suggestion(for: at(22, 0), scheduled: sleepIn.minutes(on: at(22, 0), calendar: calendar),
                                                events: [event("Flight", at(22, 7, 52), at(22, 10))],
                                                prefs: prefs, calendar: calendar)
        XCTAssertEqual(s?.suggested, 6 * 60 + 45)          // 7:52 − 65 min = 6:47 → 6:45
        XCTAssertNil(s?.current)
    }

    func testWorkPatternMakesAMissingShiftADayOff() {
        let work = [22, 26, 27, 28, 30].map { event("Office", at($0, 13), at($0, 21)) }
        let s = WakeSuggestionEngine.suggestions(schedule: schedule, events: work, prefs: CalendarPrefs(),
                                                 from: now, days: 11, calendar: calendar)
        // Fridays and Thursdays are work in the span; the 23rd and 29th have none.
        XCTAssertEqual(s.map { calendar.component(.day, from: $0.date) }, [23, 29])
        XCTAssertTrue(s.allSatisfy { $0.kind == .later })
        // One stray work meeting isn't a pattern.
        XCTAssertTrue(WakeSuggestionEngine.suggestions(schedule: schedule, events: [work[0]], prefs: CalendarPrefs(),
                                                       from: now, days: 11, calendar: calendar).isEmpty)
    }

    func testChangedDaysAndIgnoredSuggestionsAreSkipped() {
        let events = [event("Dentist", at(22, 8, 15), at(22, 9)), event("Vacation", at(23, 0), at(24, 0), allDay: true)]
        var changed = schedule
        changed.setDay(7 * 60, on: at(22, 0), calendar: calendar)
        let ignored = WakeSuggestionEngine.suggestions(schedule: changed, events: events, prefs: CalendarPrefs(),
                                                       from: now, days: 8, calendar: calendar)
        XCTAssertEqual(ignored.count, 1)
        let none = WakeSuggestionEngine.suggestions(schedule: changed, events: events, prefs: CalendarPrefs(),
                                                    from: now, days: 8, dismissed: [ignored[0].id], calendar: calendar)
        XCTAssertTrue(none.isEmpty)
    }

    func testMergeAndWords() {
        let merged = WakeSuggestionEngine.merge(
            [event("Dentist", at(22, 8, 15), at(22, 9))],
            [event("dentist ", at(22, 8, 17), at(22, 9), source: .google), event("Lunch", at(22, 12), at(22, 13), source: .google)]
        )
        XCTAssertEqual(merged.map(\.title), ["Dentist", "Lunch"])
        XCTAssertEqual(merged.first?.source, .apple)
        XCTAssertFalse(WakeSuggestionEngine.containsWord("postoffice run", "office"))
        XCTAssertFalse(WakeSuggestionEngine.containsWord("workout", "work"))
        XCTAssertTrue(WakeSuggestionEngine.containsWord("pto – beach", "pto"))
    }
}
