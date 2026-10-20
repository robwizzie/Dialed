//
//  FinalPushTests.swift
//  DialedTests
//
//  The last 14 days: when it's on, how much it tightens the target, and the
//  check-in streak.
//

import XCTest
@testable import Dialed

final class FinalPushTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func day(_ m: Int, _ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))!
    }
    private var end: Date { day(11, 19, hour: 0) }

    func testWindow() {
        XCTAssertFalse(FinalPush.isActive(end: end, now: day(11, 4), calendar: calendar))   // 15 days out
        XCTAssertTrue(FinalPush.isActive(end: end, now: day(11, 5), calendar: calendar))    // 14 days out
        XCTAssertTrue(FinalPush.isActive(end: end, now: day(11, 19, hour: 20), calendar: calendar))
        XCTAssertFalse(FinalPush.isActive(end: end, now: day(11, 20), calendar: calendar))
        XCTAssertEqual(FinalPush.daysLeft(end: end, now: day(11, 12), calendar: calendar), 7)
        XCTAssertEqual(FinalPush.phase(daysLeft: 0).title, "Final day.")
        let start = FinalPush.startMorning(end: end, calendar: calendar)!
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour], from: start), DateComponents(month: 11, day: 5, hour: 8))
    }

    func testStricterTargetStaysSane() {
        XCTAssertEqual(FinalPush.stricterTarget(normal: 2_590, pace: 2_270), 2_270)
        XCTAssertEqual(FinalPush.stricterTarget(normal: 2_590, pace: 1_500), 1_840)   // at most 750 below
        XCTAssertEqual(FinalPush.stricterTarget(normal: 1_900, pace: 1_200), 1_500)   // never under 1,500
        XCTAssertEqual(FinalPush.stricterTarget(normal: 2_200, pace: 2_600), 2_200)   // never above usual
        XCTAssertEqual(FinalPush.stricterTarget(normal: 2_200, pace: nil), 2_200)
    }

    func testCheckInStreak() {
        let yes = FinalPush.CheckIn(onPlan: true, weighedIn: true, moved: true)
        var all: [String: FinalPush.CheckIn] = [:]
        for d in 10...12 { all[FinalPush.key(day(11, d), calendar: calendar)] = yes }
        // Today (13th) not done yet: the streak still counts through yesterday.
        XCTAssertEqual(FinalPush.streak(all, now: day(11, 13), calendar: calendar), 3)
        all[FinalPush.key(day(11, 13), calendar: calendar)] = yes
        XCTAssertEqual(FinalPush.streak(all, now: day(11, 13), calendar: calendar), 4)
        all[FinalPush.key(day(11, 11), calendar: calendar)] = FinalPush.CheckIn(onPlan: false, weighedIn: true, moved: true)
        XCTAssertEqual(FinalPush.streak(all, now: day(11, 13), calendar: calendar), 2)
        XCTAssertTrue(yes.isComplete)
        XCTAssertFalse(FinalPush.CheckIn(onPlan: true).isComplete)
    }
}
