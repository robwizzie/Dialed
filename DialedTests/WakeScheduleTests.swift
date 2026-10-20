//
//  WakeScheduleTests.swift
//  DialedTests
//
//  Usual times per weekday, one-off changes for a date, and the bedtime
//  that follows.
//

import XCTest
@testable import Dialed

final class WakeScheduleTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d))! }

    func testUsualTimesAndOneDayChanges() {
        var s = WakeSchedule.standard
        XCTAssertEqual(s.minutes(on: day(20), calendar: calendar), 390)   // Tuesday 6:30
        XCTAssertEqual(s.minutes(on: day(24), calendar: calendar), 480)   // Saturday 8:00

        s.setDay(270, on: day(22), calendar: calendar)                    // early flight
        XCTAssertEqual(s.minutes(on: day(22), calendar: calendar), 270)
        XCTAssertTrue(s.isChanged(on: day(22), calendar: calendar))
        XCTAssertEqual(s.minutes(on: day(29), calendar: calendar), 390)   // next Thursday unaffected

        s.setDay(390, on: day(22), calendar: calendar)                    // back to usual clears it
        XCTAssertFalse(s.isChanged(on: day(22), calendar: calendar))

        s.setDay(nil, on: day(23), calendar: calendar)                    // day off: sleep in
        XCTAssertNil(s.wake(on: day(23), calendar: calendar))
    }

    func testBedtimeIsTheEveningBefore() {
        let s = WakeSchedule.standard
        let bed = s.bedtime(before: day(20), calendar: calendar)!
        let c = calendar.dateComponents([.day, .hour, .minute], from: bed)
        XCTAssertEqual([c.day, c.hour, c.minute], [19, 22, 30])
    }

    func testPastChangesAreForgotten() {
        var s = WakeSchedule.standard
        s.setDay(300, on: day(20), calendar: calendar)
        s.setDay(300, on: day(28), calendar: calendar)
        s.prune(before: day(25), calendar: calendar)
        XCTAssertEqual(Array(s.overrides.keys), ["2026-10-28"])
    }
}
