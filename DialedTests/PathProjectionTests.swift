//
//  PathProjectionTests.swift
//  DialedTests
//
//  "If every day were like…" picks the right days, skips unlogged and
//  unfinished ones, and turns a daily surplus/deficit into pounds.
//

import XCTest
@testable import Dialed

final class PathProjectionTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!
    private lazy var goal = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18))!   // 30 days out

    private func day(_ offset: Int, eaten: Double, active: Double? = 500, steps: Int = 8_000) -> PathProjection.DayRecord {
        let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return .init(date: date, caloriesIn: eaten, activeKcal: active, steps: steps)
    }

    func testCaloriesOutUsesWatchActiveEnergyWhenPresent() {
        XCTAssertEqual(PathProjection.caloriesOut(weight: 200, activeKcal: 600, steps: 0), 3_000)
        // No watch energy: falls back to steps (10k steps at 150 lb ≈ 400 kcal).
        XCTAssertEqual(PathProjection.caloriesOut(weight: 150, activeKcal: nil, steps: 10_000), 1_800 + 400, accuracy: 0.01)
    }

    func testBestTypicalToughestAndYesterday() {
        // 200 lb, 500 active → 2,900 out per day.
        let days = [day(-3, eaten: 2_400), day(-2, eaten: 3_400), day(-1, eaten: 2_900)]
        let s = PathProjection.scenarios(days: days, weight: 200, calorieTarget: 2_400, goalDate: goal, now: now, calendar: calendar)
        let byKind = Dictionary(uniqueKeysWithValues: s.map { ($0.kind, $0) })

        XCTAssertEqual(byKind[.yesterday]?.dailyNet ?? .nan, 0, accuracy: 0.01)
        XCTAssertEqual(byKind[.best]?.dailyNet ?? .nan, -500, accuracy: 0.01)
        XCTAssertEqual(byKind[.toughest]?.dailyNet ?? .nan, 500, accuracy: 0.01)
        XCTAssertEqual(byKind[.typical]?.dailyNet ?? .nan, 0, accuracy: 0.01)
        // 500 kcal/day for 30 days = 15,000 kcal ≈ 4.3 lb.
        XCTAssertEqual(byKind[.best]?.poundsChange ?? .nan, -500 * 30 / 3_500, accuracy: 0.01)
        XCTAssertEqual(byKind[.toughest]?.projectedWeight ?? .nan, 200 + 500 * 30 / 3_500, accuracy: 0.01)
        XCTAssertTrue(byKind[.best]!.losing)
        XCTAssertFalse(byKind[.toughest]!.losing)
        XCTAssertEqual(byKind[.plan]?.dailyNet ?? .nan, -500, accuracy: 0.01)
    }

    func testSkipsTodayAndUnderLoggedDays() {
        let days = [day(-2, eaten: 600), day(0, eaten: 2_000)]
        let s = PathProjection.scenarios(days: days, weight: 200, calorieTarget: 2_400, goalDate: goal, now: now, calendar: calendar)
        // Only the budget scenario is left.
        XCTAssertEqual(s.map(\.kind), [.plan])
    }

    func testOneLoggedDayHasNoBestOrToughest() {
        let s = PathProjection.scenarios(days: [day(-1, eaten: 2_500)], weight: 200, calorieTarget: 0, goalDate: goal, now: now, calendar: calendar)
        XCTAssertEqual(s.map(\.kind), [.yesterday])
    }

    func testSameDaysCollapseToughest() {
        let days = [day(-2, eaten: 2_500), day(-1, eaten: 2_500)]
        let s = PathProjection.scenarios(days: days, weight: 200, calorieTarget: 0, goalDate: goal, now: now, calendar: calendar)
        XCTAssertEqual(s.map(\.kind), [.yesterday, .best, .typical])
    }
}
