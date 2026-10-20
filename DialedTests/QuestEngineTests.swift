//
//  QuestEngineTests.swift
//  DialedTests
//
//  Daily quests stay put all day, skip what doesn't apply, check
//  themselves off from data, and XP climbs a gentle level curve. Plus the
//  shared habit-day streaks they're built on.
//

import XCTest
@testable import Dialed

final class QuestEngineTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testSameThreeAllDayAndRestDaysSkipTheWorkout() {
        var facts = QuestEngine.Facts(now: date(20, 9))
        facts.isWorkoutDay = false
        let morning = QuestEngine.today(date(20), facts: facts, calendar: calendar)
        facts.now = date(20, 18)
        let evening = QuestEngine.today(date(20, 18), facts: facts, calendar: calendar)
        XCTAssertEqual(morning.count, 3)
        XCTAssertEqual(morning.map(\.kind), evening.map(\.kind))
        let sixtyDays = (0..<60).flatMap { i in
            QuestEngine.today(calendar.date(byAdding: .day, value: i, to: date(1))!, facts: facts, calendar: calendar).map(\.kind)
        }
        XCTAssertFalse(sixtyDays.contains(.finishWorkout))
        XCTAssertFalse(sixtyDays.contains(.bedOnTime))   // no bedtime planned
    }

    func testQuestsCheckThemselves() {
        var facts = QuestEngine.Facts(now: date(20, 10))
        facts.proteinBefore11 = 35
        let breakfast = QuestEngine.quest(.proteinBreakfast, facts: facts)
        XCTAssertEqual(QuestEngine.status(breakfast, facts: facts, calendar: calendar), .done)

        facts.proteinBefore11 = 10
        facts.now = date(20, 12)
        XCTAssertEqual(QuestEngine.status(breakfast, facts: facts, calendar: calendar), .missed)

        facts.bedtime = date(20, 22)
        let bed = QuestEngine.quest(.bedOnTime, facts: facts)
        XCTAssertEqual(QuestEngine.status(bed, facts: facts, calendar: calendar), .claimable)
        XCTAssertEqual(QuestEngine.status(bed, facts: facts, claimed: true, calendar: calendar), .done)

        facts.now = date(20, 22)
        facts.lastMealTime = date(20, 19)
        XCTAssertEqual(QuestEngine.status(QuestEngine.quest(.kitchenClosed, facts: facts), facts: facts, calendar: calendar), .done)
    }

    func testLevels() {
        XCTAssertEqual(QuestEngine.level(xp: 0).number, 1)
        XCTAssertEqual(QuestEngine.level(xp: 100).number, 2)
        let three = QuestEngine.level(xp: 350)
        XCTAssertEqual([three.number, three.into, three.size], [3, 125, 150])
        XCTAssertEqual(three.title, "Grinder")
        XCTAssertEqual(QuestEngine.level(xp: 2_000).title, "Dialed")
    }

    func testHabitStreaks() {
        let days: [HabitDays.Day] = (1...20).map { i in
            var d = HabitDays.Day(date: date(i))
            d.miles = i == 10 ? 0.4 : 1.2
            d.protein = i >= 15 ? 160 : 100
            d.proteinTarget = 150
            d.workout = [2, 4, 5, 7, 9].contains(i)
            return d
        }
        XCTAssertEqual(HabitDays.streak(days, habit: .mile, today: date(20), calendar: calendar), .init(current: 10, best: 10))
        // Today not logged yet doesn't break yesterday's streak.
        XCTAssertEqual(HabitDays.streak(days, habit: .protein, today: date(21), calendar: calendar).current, 6)
        XCTAssertEqual(HabitDays.bestWeek(days, calendar: calendar) { $0.workout }, 4)
    }
}
