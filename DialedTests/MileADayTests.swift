//
//  MileADayTests.swift
//  DialedTests
//
//  The daily mile: measured distance beats the step estimate, the streak
//  survives an unfinished today, and the Dialed score counts the mile.
//

import XCTest
@testable import Dialed

final class MileADayTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d))!
    }

    func testDistanceWinsOverSteps() {
        XCTAssertEqual(MileADay.miles(distance: 1.3, steps: 100), 1.3)
        XCTAssertEqual(MileADay.miles(distance: nil, steps: 2_100), 1, accuracy: 1e-9)
        XCTAssertEqual(MileADay.miles(distance: 0, steps: 4_200), 2, accuracy: 1e-9)
    }

    func testStreakKeepsGoingWhileTodayIsUnfinished() {
        let history: [Date: Double] = [day(16): 1.2, day(17): 1.0, day(18): 2.0, day(19): 0.3]
        XCTAssertEqual(MileADay.streak(milesByDay: history, today: day(19).addingTimeInterval(9 * 3600), calendar: calendar), 3)
        var done = history
        done[day(19)] = 1.1
        XCTAssertEqual(MileADay.streak(milesByDay: done, today: day(19), calendar: calendar), 4)
        var gap = history
        gap[day(17)] = 0.5
        XCTAssertEqual(MileADay.streak(milesByDay: gap, today: day(19), calendar: calendar), 1)
    }

    func testDialedScoreCountsTheMile() {
        let without = DialedScore.compute(waterOz: 120, waterTargetOz: 120, protein: 190, proteinTarget: 190,
                                          calories: 2_000, calorieTarget: 2_200, miles: 0)
        let with = DialedScore.compute(waterOz: 120, waterTargetOz: 120, protein: 190, proteinTarget: 190,
                                       calories: 2_000, calorieTarget: 2_200, miles: 1.2)
        XCTAssertEqual(without, 85)
        XCTAssertEqual(with, 100)
        // Older widget snapshots with no mile still score the other three.
        XCTAssertEqual(DialedScore.compute(waterOz: 120, waterTargetOz: 120, protein: 190, proteinTarget: 190,
                                           calories: 2_000, calorieTarget: 2_200), 100)
    }
}
