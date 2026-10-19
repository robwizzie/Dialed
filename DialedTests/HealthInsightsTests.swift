//
//  HealthInsightsTests.swift
//  DialedTests
//
//  Scores stay in range and reward the right things; insights fire on
//  real differences only.
//

import XCTest
@testable import Dialed

final class HealthInsightsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func night(_ day: Int, asleep: Int, inBed: Int? = nil, deep: Int? = 80, rem: Int? = 100,
                       bedHour: Int = 22, bedMinute: Int = 30, wakes: Int? = 2, vendor: Int? = nil) -> HealthInsights.Night {
        let wake = calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
        let bed = calendar.date(from: DateComponents(year: 2026, month: 10, day: day - 1, hour: bedHour, minute: bedMinute))!
        return .init(wakeDay: wake, bedtime: bed, wakeTime: bed.addingTimeInterval(Double(inBed ?? asleep + 30) * 60),
                     inBedMinutes: inBed ?? asleep + 30, asleepMinutes: asleep, deepMinutes: deep, remMinutes: rem,
                     lightMinutes: nil, awakeMinutes: nil, awakenings: wakes, vendorScore: vendor)
    }

    func testSleepScoreRewardsLongerRestorativeSleep() {
        let good = HealthInsights.sleepScore(night(18, asleep: 460))
        let short = HealthInsights.sleepScore(night(18, asleep: 300, inBed: 420, deep: 30, rem: 40, wakes: 6))
        XCTAssertGreaterThanOrEqual(good, 85)
        XCTAssertLessThan(short, 60)
        XCTAssertEqual(HealthInsights.sleepScore(night(18, asleep: 300, vendor: 77)), 77)
    }

    func testBedtimeAcrossMidnightCompares() {
        let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 0, minute: 30))!
        let early = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 23, minute: 30))!
        XCTAssertEqual(HealthInsights.bedtimeMinutes(late, calendar: calendar) - HealthInsights.bedtimeMinutes(early, calendar: calendar), 60)
    }

    func testSleepInsights() {
        let history = (10...16).map { night($0, asleep: 420, deep: 60) }
        let last = night(17, asleep: 470, deep: 90)
        let texts = HealthInsights.sleepInsights(last: last, history: history, calendar: calendar).map(\.text)
        XCTAssertTrue(texts.contains { $0.contains("50 min more") })
        XCTAssertTrue(texts.contains { $0.contains("Deep sleep was higher") })
        XCTAssertTrue(texts.contains { $0.contains("consistent") })
    }

    func testReadinessNeedsTwoInputsAndMovesWithHRV() {
        XCTAssertNil(HealthInsights.readiness(hrv: 60, hrvBaseline: [50], restingHR: nil, rhrBaseline: [], sleepHours: nil))
        let up = HealthInsights.readiness(hrv: 60, hrvBaseline: [50, 50], restingHR: 55, rhrBaseline: [58, 58], sleepHours: 8)!
        let down = HealthInsights.readiness(hrv: 40, hrvBaseline: [50, 50], restingHR: 62, rhrBaseline: [58, 58], sleepHours: 5.5)!
        XCTAssertGreaterThan(up, 80)
        XCTAssertLessThan(down, 40)
    }

    func testNutritionScore() {
        let perfect = HealthInsights.NutritionDay(calories: 2_200, calorieTarget: 2_300, protein: 190, proteinTarget: 190,
                                                  waterOz: 120, waterTargetOz: 120, fiber: 32)
        XCTAssertEqual(HealthInsights.nutritionScore(perfect), 100)
        var over = perfect
        over.calories = 3_000
        XCTAssertLessThan(HealthInsights.nutritionScore(over), 70)
    }

    func testStreakAndInsights() {
        XCTAssertEqual(HealthInsights.streak([100, 190, 185, 200], target: 190), 3)
        let day = HealthInsights.NutritionDay(calories: 1_800, calorieTarget: 2_300, protein: 200, proteinTarget: 190,
                                              waterOz: 20, waterTargetOz: 120, fiber: 12)
        let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 21, minute: 40))!
        let texts = HealthInsights.nutritionInsights(today: day, proteinHistory: [195, 200], mealTimes: [late],
                                                     expectedFraction: 0.8, calendar: calendar).map(\.text)
        XCTAssertTrue(texts.contains { $0.contains("2 days in a row") })
        XCTAssertTrue(texts.contains { $0.contains("behind pace") })
        XCTAssertTrue(texts.contains { $0.contains("Late meals") })
        XCTAssertTrue(texts.contains { $0.contains("Fiber is 12") })
    }
}
