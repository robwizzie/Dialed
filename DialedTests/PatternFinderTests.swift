//
//  PatternFinderTests.swift
//  DialedTests
//
//  Real gaps show up in plain words; thin or small ones don't.
//

import XCTest
@testable import Dialed

final class PatternFinderTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    /// 28 days from Monday Sep 21 2026.
    private func days(_ build: (Int, Date, inout PatternFinder.Day) -> Void) -> [PatternFinder.Day] {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))!
        return (0..<28).map { i in
            let date = calendar.date(byAdding: .day, value: i, to: start)!
            var d = PatternFinder.Day(date: date, calories: 1_900, protein: 150, miles: 1.2, sleepMinutes: 420)
            build(i, date, &d)
            return d
        }
    }

    private func at(_ date: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
    }

    func testWeekendsCostCalories() {
        let data = days { _, date, d in
            if calendar.isDateInWeekend(date) { d.calories = 2_500 }
        }
        let p = PatternFinder.find(data, calendar: calendar)
        XCTAssertEqual(p.first?.id, "weekend-calories")
        XCTAssertEqual(p.first?.title, "Weekends average 600 more calories")
        XCTAssertEqual(p.first?.isGood, false)
        XCTAssertEqual(p.first?.samples, [8, 20])
    }

    func testLateMealsCostSleep() {
        // Every third day dinner at 9:45 PM; the night after is 45 min shorter.
        var lateDays = Set<Int>()
        let data = days { i, date, d in
            if i % 3 == 0 { d.lastMeal = at(date, 21, 45); lateDays.insert(i) } else { d.lastMeal = at(date, 18, 30) }
            if lateDays.contains(i - 1) { d.sleepMinutes = 375 }
        }
        let p = PatternFinder.find(data, calendar: calendar).first { $0.id == "late-meal-sleep" }
        XCTAssertEqual(p?.title, "You sleep 45 min less after late meals")
    }

    func testDrinksShowUpOnTheScale() {
        let data = days { i, _, d in
            d.weight = 206 - Double(i) * 0.1 + (i % 7 == 6 ? 1.3 : 0)   // up the morning after day 5's drinks
            d.drinks = i % 7 == 5 ? 3 : 0
        }
        let p = PatternFinder.find(data, calendar: calendar).first { $0.id == "drinks-weight" }
        XCTAssertNotNil(p)
        // +1.2 after drinks vs about −0.3 otherwise (the bump comes back off the day after).
        XCTAssertEqual(p?.title, "The morning after drinks, the scale reads 1.5 lb higher")
    }

    func testShortSleepAndMileAndProtein() {
        let data = days { i, _, d in
            if i % 4 == 0 { d.sleepMinutes = 330; d.calories = 2_400 }
            if i % 5 == 0 { d.miles = 0.3; d.calories = (d.calories ?? 0) + 300 }
        }
        let ids = Set(PatternFinder.find(data, calendar: calendar).map(\.id))
        XCTAssertTrue(ids.contains("short-sleep-calories"))
        XCTAssertTrue(ids.contains("mile-calories"))
    }

    func testNoNoise() {
        // Small wobbles and thin samples say nothing.
        let flat = days { i, _, d in d.calories = 1_900 + Double(i % 3) * 40 }
        XCTAssertTrue(PatternFinder.find(flat, calendar: calendar).isEmpty)
        let thin = Array(days { _, date, d in if calendar.isDateInWeekend(date) { d.calories = 3_000 } }.prefix(6))
        XCTAssertNil(PatternFinder.find(thin, calendar: calendar).first { $0.id == "weekend-calories" })
        // Half-logged days don't count as low days.
        let partial = days { _, date, d in if calendar.isDateInWeekend(date) { d.calories = 400 } }
        XCTAssertNil(PatternFinder.find(partial, calendar: calendar).first { $0.id == "weekend-calories" })
    }

    func testPlainNumbers() {
        XCTAssertEqual(PatternFinder.cal(612), "600")
        XCTAssertEqual(PatternFinder.minutes(38), "40 min")
        XCTAssertEqual(PatternFinder.minutes(75), "1 h 15 min")
        XCTAssertEqual(PatternFinder.signed(-0.44), "−0.4 lb")
    }
}
