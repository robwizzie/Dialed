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
        XCTAssertEqual(MileADay.miles(distance: 1.3, steps: 100, stepsPerMile: 2_100), 1.3)
        XCTAssertEqual(MileADay.miles(distance: nil, steps: 2_100, stepsPerMile: 2_100), 1, accuracy: 1e-9)
        XCTAssertEqual(MileADay.miles(distance: 0, steps: 4_800, stepsPerMile: 2_400), 2, accuracy: 1e-9)
    }

    func testStrideIsLearnedFromHealthDays() {
        // Median of 2,300 / 2,350 / 2,300; the short day and the GPS glitch are ignored.
        let days: [(steps: Double, miles: Double)] = [(2_300, 1.0), (4_700, 2.0), (1_150, 0.5), (500, 0.1), (9_000, 1.0)]
        XCTAssertEqual(MileADay.learnStride(days), 2_300)
        XCTAssertNil(MileADay.learnStride([(2_300, 1.0), (4_700, 2.0)]))
    }

    func testStreakKeepsGoingWhileTodayIsUnfinished() {
        let history: [Date: Double] = [day(16): 1.2, day(17): 1.0, day(18): 2.0, day(19): 0.3]
        XCTAssertEqual(MileADay.streak(milesByDay: history, today: day(19).addingTimeInterval(9 * 3600), goal: 1, calendar: calendar), 3)
        var done = history
        done[day(19)] = 1.1
        XCTAssertEqual(MileADay.streak(milesByDay: done, today: day(19), goal: 1, calendar: calendar), 4)
        var gap = history
        gap[day(17)] = 0.5
        XCTAssertEqual(MileADay.streak(milesByDay: gap, today: day(19), goal: 1, calendar: calendar), 1)
        // A bigger goal raises the bar.
        XCTAssertEqual(MileADay.streak(milesByDay: history, today: day(19), goal: 1.5, calendar: calendar), 1)
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

    func testWorkoutsCountTowardTheDay() {
        // Two logged walks (0.6 + 0.5 mi) beat a phone distance of 0.7.
        let r = MileADay.resolve(distance: 0.7, workoutMiles: 1.1, steps: 900, stepsPerMile: 2_100)
        XCTAssertEqual(r.miles, 1.1, accuracy: 1e-9)
        XCTAssertEqual(r.source, .workout)
        XCTAssertEqual(MileADay.resolve(distance: 1.3, workoutMiles: 1.1, steps: 0, stepsPerMile: 2_100).source, .distance)
        XCTAssertEqual(MileADay.resolve(distance: nil, workoutMiles: 0, steps: 4_200, stepsPerMile: 2_100).source, .steps)
    }

    func testHistoryStreaksAndMerge() {
        var h = MileHistory(start: day(1), days: [], updatedAt: Date())
        h.merge((1...10).map { MileDay(date: day($0), miles: [3, 4, 8].contains($0) ? 0.2 : 1.2) })
        XCTAssertEqual(h.doneCount(goal: 1), 7)
        XCTAssertEqual(h.longestStreak(goal: 1, calendar: calendar), 3)
        XCTAssertEqual(h.currentStreak(today: day(10), goal: 1, calendar: calendar), 2)
        // A late-synced workout fixes day 8.
        h.merge([MileDay(date: day(8), miles: 2, workouts: 1)])
        XCTAssertEqual(h.longestStreak(goal: 1, calendar: calendar), 6)
        let week = h.last(7, today: day(12), calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first?.date, day(6))
        XCTAssertEqual(week.last?.miles, 0)
    }
}
