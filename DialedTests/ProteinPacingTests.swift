//
//  ProteinPacingTests.swift
//  DialedTests
//
//  Protein pace follows when you usually eat, sizes the fix to the gap,
//  and only nudges when it's worth it.
//

import XCTest
@testable import Dialed

final class ProteinPacingTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testBehindMidAfternoonSuggestsAShake() {
        let s = ProteinPacing.status(actual: 60, target: 180, curve: ProteinPacing.defaultCurve,
                                     now: at(20, 15), lastMealAt: at(20, 12), calendar: calendar)
        XCTAssertEqual(s.gap, 33.6, accuracy: 1)
        XCTAssertTrue(s.shouldNudge)
        XCTAssertEqual(s.suggestion?.name, "Protein shake")
        XCTAssertEqual(s.message, "You're at 60 g by 3 PM. A protein shake (24 g) now keeps you on track.")
    }

    func testNoNudgeRightAfterAMealOrWhenOnPace() {
        let justAte = ProteinPacing.status(actual: 60, target: 180, curve: ProteinPacing.defaultCurve,
                                           now: at(20, 15), lastMealAt: at(20, 14), calendar: calendar)
        XCTAssertFalse(justAte.shouldNudge)
        let onPace = ProteinPacing.status(actual: 95, target: 180, curve: ProteinPacing.defaultCurve,
                                          now: at(20, 15), calendar: calendar)
        XCTAssertFalse(onPace.shouldNudge)
        XCTAssertNil(onPace.suggestion)
    }

    func testLateEaterIsNotBehindAtNoon() {
        var meals: [ProteinPacing.Meal] = []
        for d in 10...19 {
            meals.append(.init(date: at(d, 14), protein: 60))
            meals.append(.init(date: at(d, 20), protein: 100))
        }
        let curve = ProteinPacing.learn(meals, now: at(20, 9), calendar: calendar)
        XCTAssertTrue(curve.learned)
        XCTAssertLessThan(curve.share(at: at(20, 12), calendar: calendar), 0.1)
        let s = ProteinPacing.status(actual: 0, target: 180, curve: curve, now: at(20, 12), calendar: calendar)
        XCTAssertFalse(s.shouldNudge)
        // Too little history falls back to the default.
        XCTAssertFalse(ProteinPacing.learn(Array(meals.prefix(4)), now: at(20, 9), calendar: calendar).learned)
    }

    func testSmartReminderUsesYourPace() {
        var settings = ReminderSettings()
        settings.enabled = true
        var inputs = ReminderPlanner.Inputs(now: at(20, 9))
        inputs.proteinGrams = 60
        inputs.proteinTarget = 180
        inputs.proteinCurve = ProteinPacing.defaultCurve
        let nudge = ReminderPlanner.plan(inputs, settings: settings, calendar: calendar).first { $0.title == "Protein check 🍗" }
        XCTAssertNotNil(nudge)
        XCTAssertTrue(nudge?.body.hasPrefix("You're at 60 g by 3:30 PM.") ?? false)
        // Caught up: no nudge.
        inputs.proteinGrams = 110
        XCTAssertNil(ReminderPlanner.plan(inputs, settings: settings, calendar: calendar).first { $0.title == "Protein check 🍗" })
    }

    func testSnackSizes() {
        XCTAssertEqual(ProteinPacing.suggestion(for: 12)?.name, "Greek yogurt")
        XCTAssertEqual(ProteinPacing.suggestion(for: 30)?.name, "Protein shake")
        XCTAssertEqual(ProteinPacing.suggestion(for: 45)?.name, "Tuna, 1 can")
        XCTAssertNil(ProteinPacing.suggestion(for: 5))
        XCTAssertEqual(ProteinPacing.options.first { $0.name == "Protein shake" }?.protein, 24)
    }
}
