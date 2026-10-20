//
//  WeeklyReportTests.swift
//  DialedTests
//
//  The Sunday you-vs-Dave report, and the monthly photo-day date math.
//

import XCTest
@testable import Dialed

final class WeeklyReportTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func day(_ m: Int, _ d: Int, _ h: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    private var inputs: WeeklyHeadToHeadReport.Inputs {
        let bet = SideBets.Bet(id: "b1", week: "2026-10-19", metric: .steps, stake: "Loser buys wings 🍗",
                               proposer: .you, status: .active, youScore: 70_000, friendScore: 55_000)
        return WeeklyHeadToHeadReport.Inputs(
            weekStart: day(10, 19), challengeStart: day(10, 1), scoring: .pounds, friendName: "Dave",
            you: .init(startTrend: 206, endTrend: 204.2, steps: 70_000, miles: 14.2, workouts: 4, prs: 2, xp: 310),
            friend: .init(startTrend: 220, endTrend: 219.3, steps: 55_000, workouts: 5),
            yourStartWeight: 210, friendStartWeight: 224, bet: bet, raceStatus: .behind, neededRate: 1.6,
            leader: .you, margin: 2.3)
    }

    func testWeekNumbers() {
        XCTAssertEqual(WeeklyHeadToHeadReport.weekNumber(challengeStart: day(10, 1), weekStart: day(10, 19), calendar: calendar), 4)
        XCTAssertEqual(WeeklyHeadToHeadReport.weekNumber(challengeStart: day(10, 1), weekStart: day(10, 1), calendar: calendar), 1)
    }

    func testWeekTrendStartsBeforeMonday() {
        let readings = [WeightReading(date: day(10, 18), pounds: 206, source: .manual)]
            + (19...25).map { WeightReading(date: day(10, $0), pounds: 206 - Double($0 - 18) * 0.3, source: .manual) }
        let t = WeeklyHeadToHeadReport.weekTrend(readings, weekStart: day(10, 21), calendar: calendar)
        XCTAssertEqual(t.start, 206)
        XCTAssertLessThan(t.end ?? 999, 206)
        XCTAssertNil(WeeklyHeadToHeadReport.weekTrend([], weekStart: day(10, 21), calendar: calendar).start)
    }

    func testYouTakeTheWeekAndDaveBuysWings() {
        let r = WeeklyHeadToHeadReport.build(inputs, calendar: calendar)
        XCTAssertEqual(r.headline, "You took week 4 by 1.1 lb")
        XCTAssertEqual(r.week, "2026-10-19")
        XCTAssertEqual(r.weekWinner, "you")
        XCTAssertEqual(r.rows.first { $0.id == "workouts" }?.winner, "friend")
        XCTAssertNil(r.rows.first { $0.id == "prs" }?.winner)
        XCTAssertEqual(r.betLine, "Dave buys wings 🍗")
        XCTAssertEqual(r.subline, "You won 2 of 3 categories this week.")
        XCTAssertTrue(r.nudge.contains("1.6 lb a week"))
        XCTAssertEqual(r.standing, "Overall you lead by 2.3 lb.")
    }

    func testPercentScoringAndSoloWeeks() {
        var i = inputs
        i.scoring = .percent
        i.friend.endTrend = 216
        i.bet = nil
        let dave = WeeklyHeadToHeadReport.build(i, calendar: calendar)
        XCTAssertTrue(dave.headline.hasPrefix("Dave took week 4 by"))
        XCTAssertNil(dave.betLine)

        i.friend = .init()
        i.scoring = .pounds
        let solo = WeeklyHeadToHeadReport.build(i, calendar: calendar)
        XCTAssertEqual(solo.headline, "Week 4: you're down 1.8 lb")
        XCTAssertTrue(WeeklyHeadToHeadReport.text(solo).hasPrefix("📊 Week 4"))
    }

    func testMonthlyPhotoDay() {
        XCTAssertEqual(MonthlyPhotoReminder.defaultDay(firstPhoto: day(1, 31), calendar: calendar), 28)
        XCTAssertEqual(MonthlyPhotoReminder.defaultDay(firstPhoto: day(3, 12), calendar: calendar), 12)
        XCTAssertEqual(MonthlyPhotoReminder.defaultDay(firstPhoto: nil), 1)
        let m = MonthlyPhotoReminder(enabled: true, day: 20, hour: 9, minute: 0)
        XCTAssertEqual(m.next(after: day(10, 20, 8), calendar: calendar), day(10, 20, 9))
        XCTAssertEqual(m.next(after: day(10, 20, 10), calendar: calendar), day(11, 20, 9))
        XCTAssertEqual(m.next(after: day(12, 25, 10), calendar: calendar),
                       calendar.date(from: DateComponents(year: 2027, month: 1, day: 20, hour: 9)))
        XCTAssertTrue(m.isPhotoDay(day(10, 20), calendar: calendar))
    }
}
