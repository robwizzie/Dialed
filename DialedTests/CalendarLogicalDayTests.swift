//
//  CalendarLogicalDayTests.swift
//  DialedTests
//
//  Locks in the 4 AM cutoff semantics for the shared
//  Calendar.logicalStartOfDay(for:) helper — every event-querying call
//  site relies on this matching ContextEvent.logicalDate.
//

import XCTest
@testable import Dialed

final class CalendarLogicalDayTests: XCTestCase {

    private let cal = Calendar.current

    // Builds a wall-clock Date(year, month, day, hour, minute) without
    // dragging in DST quirks — we only need a specific hour-of-day.
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = mo; dc.day = d; dc.hour = h; dc.minute = m
        return cal.date(from: dc)!
    }

    // MARK: - Basic cutoff

    func testLogicalStartOfDay_beforeCutoffRollsBack() {
        // 1 AM Tuesday → Monday 00:00 logically.
        let lateNight = date(2026, 5, 26, 1, 30)
        let logicalDay = cal.logicalStartOfDay(for: lateNight)
        let expectedMonday = cal.startOfDay(for: date(2026, 5, 25, 12))
        XCTAssertEqual(logicalDay, expectedMonday)
    }

    func testLogicalStartOfDay_atCutoffBoundaryGoesForward() {
        // 4 AM Tuesday → Tuesday 00:00 logically (cutoff exclusive).
        let cutoff = date(2026, 5, 26, 4, 0)
        let logicalDay = cal.logicalStartOfDay(for: cutoff)
        let expectedTuesday = cal.startOfDay(for: cutoff)
        XCTAssertEqual(logicalDay, expectedTuesday)
    }

    func testLogicalStartOfDay_afterCutoffStaysOnSameDay() {
        // 10 AM Tuesday → Tuesday 00:00.
        let morning = date(2026, 5, 26, 10, 15)
        let logicalDay = cal.logicalStartOfDay(for: morning)
        let expectedTuesday = cal.startOfDay(for: morning)
        XCTAssertEqual(logicalDay, expectedTuesday)
    }

    func testLogicalStartOfDay_lateEveningStaysOnSameDay() {
        // 11:55 PM Tuesday → Tuesday 00:00.
        let lateEvening = date(2026, 5, 26, 23, 55)
        let logicalDay = cal.logicalStartOfDay(for: lateEvening)
        XCTAssertEqual(logicalDay, cal.startOfDay(for: lateEvening))
    }

    // MARK: - Matches ContextEvent.logicalDate

    /// Sanity check: the shared helper produces the same answer the model
    /// uses when it stamps logicalDate at insertion time. If these ever
    /// diverge, queries will silently miss data.
    func testLogicalStartOfDay_matchesContextEventStorage() {
        let samples: [Date] = [
            date(2026, 5, 26, 0, 1),    // just after midnight
            date(2026, 5, 26, 3, 59),   // just before cutoff
            date(2026, 5, 26, 4, 0),    // at cutoff
            date(2026, 5, 26, 12, 0),   // noon
            date(2026, 5, 26, 23, 59)   // just before midnight
        ]
        for sample in samples {
            XCTAssertEqual(
                cal.logicalStartOfDay(for: sample),
                ContextEvent.logicalDate(for: sample),
                "Cutoff helper diverged from ContextEvent storage at \(sample)"
            )
        }
    }

    // MARK: - isDateInLogicalDay

    func testIsDateInLogicalDay_lateNightAndPreviousEveningAgree() {
        let mondayEvening = date(2026, 5, 25, 22, 0)
        let tuesdayLateNight = date(2026, 5, 26, 1, 30)  // logically still Monday
        XCTAssertTrue(cal.isDateInLogicalDay(mondayEvening, of: tuesdayLateNight))
    }

    func testIsDateInLogicalDay_afterCutoffSeparatesDays() {
        let mondayEvening = date(2026, 5, 25, 22, 0)
        let tuesdayMorning = date(2026, 5, 26, 8, 0)
        XCTAssertFalse(cal.isDateInLogicalDay(mondayEvening, of: tuesdayMorning))
    }
}
