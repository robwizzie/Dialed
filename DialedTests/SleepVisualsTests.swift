//
//  SleepVisualsTests.swift
//  DialedTests
//
//  Morning sky tiers from the score, and tonight's bedtime from your
//  scheduled wake-up with a capped slice of sleep debt.
//

import XCTest
@testable import Dialed

final class SleepVisualsTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }
    private func clock(_ d: Date) -> String {
        let c = calendar.dateComponents([.day, .hour, .minute], from: d)
        return String(format: "%d %d:%02d", c.day!, c.hour!, c.minute!)
    }

    func testScoreTiers() {
        XCTAssertEqual(SleepVisuals.MorningTier(score: 96), .radiant)
        XCTAssertEqual(SleepVisuals.MorningTier(score: 72), .mellow)
        XCTAssertEqual(SleepVisuals.MorningTier(score: 50), .hazy)
        XCTAssertEqual(SleepVisuals.MorningTier(score: 30), .drizzly)
    }

    func testScheduledWakeWinsAndDebtIsCapped() {
        var schedule = WakeSchedule.standard
        schedule.setUsual(510, weekday: 4)   // Wednesdays 8:30
        // Tuesday 9:05 PM, 2.4 h short this week, usual wake 10:17.
        let t = SleepVisuals.tonight(schedule: schedule, learnedWakeMinutes: 617, debtHours: 2.4,
                                     now: at(20, 21, 5), calendar: calendar)!
        XCTAssertTrue(t.fromSchedule)
        XCTAssertEqual(clock(t.wake), "21 8:30")
        XCTAssertEqual(t.extraMinutes, 45)            // a third of 2.4 h would be 48 min
        XCTAssertEqual(clock(t.bedtime), "20 23:45")  // 8 h goal + 45 min
        XCTAssertEqual(clock(t.windDown), "20 23:15")
        XCTAssertEqual(SleepVisuals.countdown(t, now: at(20, 21, 5)), "Wind down in 2 h 10 m")
        // Only within 3 h of wind-down: not at 10 AM, yes at 9:05 PM.
        XCTAssertNil(SleepVisuals.countdownIfSoon(t, now: at(20, 10)))
        XCTAssertEqual(SleepVisuals.countdownIfSoon(t, now: at(20, 21, 5)), "Wind down in 2 h 10 m")
    }

    func testAfterMidnightStillPlansForThisMorning() {
        var schedule = WakeSchedule.standard
        schedule.setUsual(510, weekday: 4)
        let t = SleepVisuals.tonight(schedule: schedule, learnedWakeMinutes: nil, debtHours: 0,
                                     now: at(21, 1), calendar: calendar)!
        XCTAssertEqual(clock(t.wake), "21 8:30")
        XCTAssertEqual(SleepVisuals.countdown(t, now: at(21, 1)), "Past bedtime. Lights out now")
    }

    func testFallsBackToYourUsualWake() {
        let t = SleepVisuals.tonight(schedule: nil, learnedWakeMinutes: 617, debtHours: 0,
                                     now: at(20, 21), calendar: calendar)!
        XCTAssertFalse(t.fromSchedule)
        XCTAssertEqual(clock(t.wake), "21 10:17")
        XCTAssertNil(SleepVisuals.tonight(schedule: nil, learnedWakeMinutes: nil, debtHours: 1, now: at(20, 21), calendar: calendar))
    }

    func testVerdictFoldsInTheWeekAndTheSunRidesTheScore() {
        let great = SleepVisuals.MorningTier(score: 96)
        XCTAssertEqual(great.verdict(weekDelta: 3), "Fully charged. Go take the day. 3 above your week.")
        XCTAssertEqual(great.verdict(weekDelta: 1), great.verdict)   // too small to mention
        XCTAssertEqual(great.verdict(weekDelta: nil), great.verdict)
        XCTAssertEqual(SleepVisuals.MorningTier(score: 40).verdict(weekDelta: -8),
                       "Rough night. Be kind to yourself today. 8 under your week.")
        XCTAssertEqual(SleepVisuals.arcProgress(score: 96), 0.96, accuracy: 0.001)
        XCTAssertEqual(SleepVisuals.arcProgress(score: 0), 0.04, accuracy: 0.001)   // still peeks over the horizon
        XCTAssertEqual(SleepVisuals.arcProgress(score: 120), 1)
    }
}
