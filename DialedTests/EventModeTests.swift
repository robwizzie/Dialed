//
//  EventModeTests.swift
//  DialedTests
//
//  The wedding run-up: countdown, the look-your-best week, the day itself
//  (nothing tracked, streaks safe), and the day after.
//

import XCTest
@testable import Dialed

final class EventModeTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func day(_ m: Int, _ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))!
    }

    func testPhases() {
        let wedding = day(11, 19, hour: 16)
        XCTAssertEqual(EventMode.phase(event: wedding, now: day(10, 20), calendar: calendar), .countdown(daysLeft: 30))
        XCTAssertEqual(EventMode.phase(event: wedding, now: day(11, 12), calendar: calendar), .lookYourBest(daysLeft: 7))
        XCTAssertEqual(EventMode.phase(event: wedding, now: day(11, 18, hour: 23), calendar: calendar), .lookYourBest(daysLeft: 1))
        XCTAssertEqual(EventMode.phase(event: wedding, now: day(11, 19, hour: 7), calendar: calendar), .eventDay)
        XCTAssertEqual(EventMode.phase(event: wedding, now: day(11, 20), calendar: calendar), .recovery)
        XCTAssertEqual(EventMode.phase(event: wedding, now: day(11, 22), calendar: calendar), .none)
        XCTAssertTrue(EventMode.isEventDay(event: wedding, on: day(11, 19, hour: 22), calendar: calendar))
        XCTAssertFalse(EventMode.isEventDay(event: nil, on: day(11, 19), calendar: calendar))
    }

    func testLookYourBestWeek() {
        XCTAssertNil(EventMode.carbTarget(daysLeft: 8))
        XCTAssertEqual(EventMode.carbTarget(daysLeft: 6), 150...180)
        XCTAssertEqual(EventMode.carbTarget(daysLeft: 2), 100...130)

        let early = EventMode.checklist(daysLeft: 6, bedtime: "10:30 PM")
        XCTAssertEqual(early.first { $0.id == "water" }?.title, "100+ oz of water")
        XCTAssertEqual(early.first { $0.id == "sleep" }?.title, "In bed by 10:30 PM")
        XCTAssertFalse(early.contains { $0.id == "fiber" })

        // Last two days: keep drinking normally (no water cutting), lighter fiber.
        let late = EventMode.checklist(daysLeft: 2, bedtime: nil)
        XCTAssertEqual(late.first { $0.id == "water" }?.title, "Drink normally")
        XCTAssertTrue(late.contains { $0.id == "fiber" })
        XCTAssertTrue(EventMode.checklist(daysLeft: 9, bedtime: nil).isEmpty)
        XCTAssertEqual(EventMode.countdownTitle("Brother's wedding"), "Suit-fit countdown")
    }

    func testEventDayDoesNotBreakAStreak() {
        func d(_ n: Int, mile: Bool, exempt: Bool = false) -> HabitDays.Day {
            var day = HabitDays.Day(date: calendar.date(byAdding: .day, value: n, to: day(11, 15))!)
            day.miles = mile ? 1.2 : 0
            day.exempt = exempt
            return day
        }
        // Four mile days, the wedding (no mile, exempt), then two more.
        let days = [d(0, mile: true), d(1, mile: true), d(2, mile: true), d(3, mile: true),
                    d(4, mile: false, exempt: true), d(5, mile: true), d(6, mile: true)]
        let s = HabitDays.streak(days, habit: .mile, today: days.last!.date, calendar: calendar)
        XCTAssertEqual(s.current, 6)
        XCTAssertEqual(s.best, 6)
    }
}
