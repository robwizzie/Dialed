//
//  WrappedBuilderTests.swift
//  DialedTests
//
//  The challenge recap: the right cards with the right numbers, and cards
//  without data left out.
//

import XCTest
@testable import Dialed

final class WrappedBuilderTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func day(_ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: m, day: d))! }
    private func plus(_ n: Int, _ from: Date) -> Date { calendar.date(byAdding: .day, value: n, to: from)! }

    /// 20 days in: 210 → ~205 with noise; Dave drops 3 lb in the first days, then stalls.
    private var inputs: WrappedBuilder.Inputs {
        let readings = (0..<20).map { i in
            WeightReading(date: plus(i, day(10, 1)).addingTimeInterval(7 * 3600),
                          pounds: 210 - Double(i) * 0.25 + (i % 3 == 0 ? 0.6 : 0), source: .manual)
        }
        var miles: [Date: Double] = [:]
        for i in 0..<20 where i != 5 { miles[plus(i, day(10, 1))] = 1.2 }
        let sets: [StrengthMilestones.SetRecord] = [
            .init(exercise: "Bench press", date: day(9, 20), weight: 135, reps: 8),
            .init(exercise: "Bench press", date: day(10, 6), weight: 145, reps: 8),
            .init(exercise: "Bench press", date: day(10, 13), weight: 155, reps: 8),
            .init(exercise: "Bench press", date: day(10, 13), weight: 155, reps: 6)
        ]
        return WrappedBuilder.Inputs(
            friendName: "Dave", start: day(10, 1), end: day(11, 19), now: day(10, 20), scoring: .pounds,
            series: WeightChallengeEngine.dailySeries(readings, calendar: calendar), friendStart: 220,
            friendWeighIns: [(day(10, 3), 217), (day(10, 10), 216.5), (day(10, 17), 216.2)],
            milesByDay: miles, mileGoal: 1, sets: sets, workoutDays: [day(10, 6), day(10, 13)],
            foodLoggedDays: Set((0..<15).map { plus($0, day(10, 1)) }),
            funActivities: [("Pickleball", day(10, 7), 60), ("Pickleball", day(10, 14), 55), ("Golf", day(10, 11), 120)])
    }

    private func card(_ kind: WrappedBuilder.Card.Kind, in cards: [WrappedBuilder.Card]) -> WrappedBuilder.Card? {
        cards.first { $0.kind == kind }
    }

    func testTheStorySoFar() {
        let cards = WrappedBuilder.build(inputs, calendar: calendar)
        XCTAssertEqual(cards.first?.kind, .intro)
        XCTAssertEqual(cards.last?.kind, .final)
        XCTAssertEqual(card(.intro, in: cards)?.eyebrow, "DIALED WRAPPED · SO FAR")
        XCTAssertEqual(card(.miles, in: cards)?.title, "19 mile days out of 20")
        XCTAssertEqual(card(.miles, in: cards)?.detail.first, "Longest streak: 14 days")
        XCTAssertEqual(card(.prs, in: cards)?.value, "2")                       // 145 then 155
        XCTAssertEqual(card(.habit, in: cards)?.title, "You weighed in 20 of 20 days")
        XCTAssertEqual(card(.fun, in: cards)?.title, "Pickleball")
        XCTAssertEqual(card(.final, in: cards)?.title, "Right now: you lead")
    }

    func testThePassingMoment() {
        let passed = card(.passed, in: WrappedBuilder.build(inputs, calendar: calendar))
        XCTAssertEqual(passed?.title, "You passed Dave")
        XCTAssertEqual(passed?.detail.first?.hasPrefix("Day 14"), true)
    }

    func testCardsWithoutDataAreLeftOut() {
        var bare = inputs
        bare.sets = []
        bare.workoutDays = []
        bare.funActivities = []
        bare.milesByDay = [:]
        let kinds = WrappedBuilder.build(bare, calendar: calendar).map(\.kind)
        XCTAssertFalse(kinds.contains(.lifting))
        XCTAssertFalse(kinds.contains(.prs))
        XCTAssertFalse(kinds.contains(.fun))
        XCTAssertFalse(kinds.contains(.miles))
        XCTAssertTrue(kinds.contains(.lost))
    }

    func testFinishedSaysSo() {
        var done = inputs
        done.now = day(11, 20)
        let cards = WrappedBuilder.build(done, calendar: calendar)
        XCTAssertEqual(cards.first?.eyebrow, "DIALED WRAPPED")
        XCTAssertTrue(card(.final, in: cards)?.title.hasPrefix("Final") ?? false)
    }

    func testLongestStreak() {
        XCTAssertEqual(WrappedBuilder.longestStreak([day(10, 1), day(10, 2), day(10, 3), day(10, 5), day(10, 6)], calendar: calendar), 3)
    }
}
