//
//  DaySuggestionsTests.swift
//  DialedTests
//
//  Day stepping stays in the past, and what's still waiting from recent
//  days: unnamed stretches and unlogged gym sessions, newest first.
//

import XCTest
@testable import Dialed

final class DaySuggestionsTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testStepsNeverPassToday() {
        let today = at(20, 9)
        XCTAssertEqual(DayNavigation.step(today, by: 1, today: today, calendar: calendar), calendar.startOfDay(for: today))
        XCTAssertEqual(DayNavigation.step(today, by: -2, today: today, calendar: calendar), calendar.startOfDay(for: at(18, 1)))
        XCTAssertTrue(DayNavigation.canGoForward(at(19, 3), today: today, calendar: calendar))
        XCTAssertFalse(DayNavigation.canGoForward(today, today: today, calendar: calendar))
        XCTAssertEqual(DayNavigation.label(today, today: today, calendar: calendar), "Today")
        XCTAssertEqual(DayNavigation.label(at(19, 8), today: today, calendar: calendar), "Yesterday")
    }

    func testPendingSkipsLoggedDaysRunsAndDismissed() {
        let lift = DetectedWorkout(id: "a", title: "Strength", kind: .strength, start: at(18, 18), end: at(18, 19),
                                   miles: nil, calories: 300, source: "Watch")
        let loggedLift = DetectedWorkout(id: "b", title: "Strength", kind: .strength, start: at(17, 18), end: at(17, 19),
                                         miles: nil, calories: 300, source: "Watch")
        let run = DetectedWorkout(id: "c", title: "Run", kind: .run, start: at(18, 7), end: at(18, 8),
                                  miles: 3, calories: 300, source: "Watch")
        let bout = ActiveBouts.Bout(start: at(19, 17), end: at(19, 18), averageBPM: 130, peakBPM: 150, effort: 0.5, calories: 500)

        let items = DaySuggestions.pending(bouts: [bout], workouts: [lift, loggedLift, run],
                                           loggedDays: [calendar.startOfDay(for: at(17, 1))], dismissed: [], calendar: calendar)
        XCTAssertEqual(items.map(\.kind), [.activity, .workout])
        XCTAssertEqual(items.last?.workout?.id, "a")
        XCTAssertEqual(items.first?.calories, 500)

        XCTAssertTrue(DaySuggestions.pending(bouts: [], workouts: [lift], loggedDays: [], dismissed: ["a"],
                                             calendar: calendar).isEmpty)
    }
}
