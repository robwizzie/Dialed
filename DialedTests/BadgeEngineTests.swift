//
//  BadgeEngineTests.swift
//  DialedTests
//
//  Badges unlock from the shared habit days and totals, show progress when
//  locked, and "leading your friend" counts consecutive days ahead.
//

import XCTest
@testable import Dialed

final class BadgeEngineTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func date(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day))! }

    private var days: [HabitDays.Day] {
        (1...20).map { i in
            var d = HabitDays.Day(date: date(i))
            d.miles = i == 10 ? 0.4 : 1.2
            d.foodEntries = 3
            d.calories = 2_000
            d.calorieBudget = 2_400
            d.workout = [2, 4, 5, 7, 9].contains(i)
            d.weighedIn = i >= 14
            d.waterOz = 110
            return d
        }
    }

    func testUnlocksAndProgress() {
        let statuses = BadgeEngine.evaluate(.init(days: days, today: date(20), lostByTrend: 6.2, totalMiles: 40,
                                                  prCount: 2, level: 4, questSweeps: 1), calendar: calendar)
        let unlocked = Set(statuses.filter(\.unlocked).map(\.badge.id))
        XCTAssertEqual(unlocked, ["down5", "mile7", "pr1", "log7", "weigh7", "water7", "workout4"])

        let mile14 = statuses.first { $0.badge.id == "mile14" }!
        XCTAssertEqual(mile14.progressText, "10 of 14 days")
        XCTAssertEqual(mile14.progress, 10.0 / 14, accuracy: 0.001)
        XCTAssertEqual(BadgeEngine.catalog.count, statuses.count)
    }

    func testLongestLead() {
        let lead = BadgeEngine.longestLead(
            yours: [(date(1), 210), (date(8), 207), (date(15), 204)], yourStart: 210,
            friend: [(date(1), 220), (date(10), 219)], friendStart: 220,
            percent: false, from: date(1), to: date(20), calendar: calendar)
        XCTAssertEqual(lead, 13)   // ahead from Oct 8 through Oct 20
    }
}
