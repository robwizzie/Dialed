//
//  DayLoadKitTests.swift
//  DialedTests
//
//  A slow source times out without holding up the caller; a quick one
//  comes through; days cache under one key.
//

import XCTest
@testable import Dialed

final class DayLoadKitTests: XCTestCase {

    func testQuickWorkComesThrough() async {
        let value = await DayLoadKit.withTimeout(seconds: 1) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testSlowWorkTimesOutPromptly() async {
        let started = Date()
        let value: Int? = await DayLoadKit.withTimeout(seconds: 0.2) {
            // Ignores cancellation, like a HealthKit query that never answers.
            while Date().timeIntervalSince(started) < 3 { try? await Task.sleep(nanoseconds: 50_000_000) }
            return 1
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testKeyIsPerCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 7))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23))!
        XCTAssertEqual(DayLoadKit.key(morning, calendar: calendar), "2026-10-19")
        XCTAssertEqual(DayLoadKit.key(morning, calendar: calendar), DayLoadKit.key(night, calendar: calendar))
    }
}
