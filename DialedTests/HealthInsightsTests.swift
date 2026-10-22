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
        // Dialed's own score wins; the watch's stays on the night for comparison.
        let withVendor = night(18, asleep: 300, vendor: 77)
        XCTAssertEqual(HealthInsights.sleepScore(withVendor), HealthInsights.sleepScore(night(18, asleep: 300)))
        XCTAssertEqual(withVendor.vendorScore, 77)
    }

    func testBreakdownAddsUpToTheScore() {
        let n = night(18, asleep: 450, inBed: 473, deep: 90, rem: 90, wakes: 2)
        let b = HealthInsights.scoreBreakdown(n)
        XCTAssertEqual(b.duration, 50, accuracy: 0.01)
        XCTAssertEqual(b.efficiency, 20, accuracy: 0.01)    // 95 % asleep in bed
        XCTAssertEqual(b.restorative, 20, accuracy: 0.01)   // 40 % deep + REM
        XCTAssertEqual(b.wakeUps, 7, accuracy: 0.01)
        XCTAssertEqual(b.total, HealthInsights.sleepScore(n))
        XCTAssertEqual(b.total, 97)
    }

    func testShortNightsAreCapped() {
        // Near-perfect quality can't carry a short night to "Good".
        let short = night(18, asleep: 294, inBed: 305, deep: 70, rem: 60, wakes: 0)
        let b = HealthInsights.scoreBreakdown(short)
        XCTAssertGreaterThan(b.points, 70)
        XCTAssertEqual(b.total, 59)
        XCTAssertEqual(HealthInsights.sleepScore(night(18, asleep: 340, inBed: 350, deep: 80, rem: 70, wakes: 0)), 69)
        XCTAssertNil(HealthInsights.scoreBreakdown(night(18, asleep: 360)).cap)
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

    // MARK: - Split nights

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func piece(_ start: Date, _ end: Date, asleep: Int, deep: Int? = 40) -> HealthInsights.Night {
        .init(wakeDay: calendar.startOfDay(for: end), bedtime: start, wakeTime: end,
              inBedMinutes: Int(end.timeIntervalSince(start) / 60), asleepMinutes: asleep,
              deepMinutes: deep, remMinutes: 30, lightMinutes: asleep - 70, awakeMinutes: 5, awakenings: 1, vendorScore: 80)
    }

    func testCombineJoinsASplitNight() throws {
        // 11 PM–3 AM, up for 40 min, back down 3:40–7 AM.
        let first = piece(at(18, 23), at(19, 3), asleep: 230)
        let second = piece(at(19, 3, 40), at(19, 7), asleep: 190)
        let night = try XCTUnwrap(HealthInsights.combine([second, first]))
        XCTAssertEqual(night.bedtime, at(18, 23))
        XCTAssertEqual(night.wakeTime, at(19, 7))
        XCTAssertEqual(night.asleepMinutes, 420)
        XCTAssertEqual(night.inBedMinutes, 480)
        XCTAssertEqual(night.awakeMinutes, 5 + 5 + 40)
        XCTAssertEqual(night.awakenings, 3)
        XCTAssertEqual(night.deepMinutes, 80)
        XCTAssertEqual(night.periods.count, 2)
        XCTAssertNil(night.vendorScore, "A watch score for one piece isn't the whole night's")
    }

    func testCombineDropsDuplicatesAndNaps() throws {
        let main = piece(at(18, 23), at(19, 7), asleep: 440)
        let duplicate = piece(at(18, 23, 5), at(19, 6, 50), asleep: 400)
        let nap = piece(at(19, 14), at(19, 14, 40), asleep: 35)
        let night = try XCTUnwrap(HealthInsights.combine([nap, duplicate, main]))
        XCTAssertEqual(night.asleepMinutes, 440)
        XCTAssertEqual(night.vendorScore, 80)
        XCTAssertEqual(night.periods.count, 1)
        XCTAssertNil(HealthInsights.combine([]))
    }

    // MARK: - Tonight

    func testSleepPlanAddsSomeDebtToTheTarget() throws {
        let rested = (12...18).map { night($0, asleep: 450) }
        let plan = try XCTUnwrap(HealthInsights.sleepPlan(history: rested, calendar: calendar))
        XCTAssertEqual(plan.debtHours, 0, accuracy: 0.01)
        XCTAssertEqual(plan.targetHours, 7.5, accuracy: 0.01)
        // Bed 10:30 PM + 480 min in bed → wake 6:30 AM → asleep by 11:00 PM.
        XCTAssertEqual(plan.wakeMinutes, 6 * 60 + 30)
        XCTAssertEqual(plan.bedtimeMinutes, 23 * 60)

        let short = (12...18).map { night($0, asleep: 360) }   // 1.5 h short × 7
        let catchUp = try XCTUnwrap(HealthInsights.sleepPlan(history: short, calendar: calendar))
        XCTAssertEqual(catchUp.debtHours, 10.5, accuracy: 0.01)
        XCTAssertEqual(catchUp.targetHours, 8.5, accuracy: 0.01, "Payback is capped at an extra hour")
        XCTAssertNil(HealthInsights.sleepPlan(history: Array(short.prefix(2)), calendar: calendar))
    }

    // MARK: - Stress

    func testStressSitsBalancedAtBaselineAndRisesWithStrain() throws {
        let normal = try XCTUnwrap(HealthInsights.stress(hrv: 60, hrvBaseline: [60, 60], restingHR: 58, rhrBaseline: [58, 58],
                                                          sleepHours: 7.5, respiratory: 15, respBaseline: [15, 15]))
        XCTAssertEqual(normal.label, "Balanced")
        let strained = try XCTUnwrap(HealthInsights.stress(hrv: 42, hrvBaseline: [60, 60], restingHR: 64, rhrBaseline: [58, 58],
                                                            sleepHours: 5, respiratory: 17, respBaseline: [15, 15]))
        XCTAssertGreaterThanOrEqual(strained.score, 90)
        XCTAssertEqual(strained.label, "High")
        let relaxed = try XCTUnwrap(HealthInsights.stress(hrv: 75, hrvBaseline: [60, 60], restingHR: 54, rhrBaseline: [58, 58],
                                                           sleepHours: 8.5, respiratory: nil, respBaseline: []))
        XCTAssertEqual(relaxed.label, "Calm")
        XCTAssertEqual(relaxed.contributors.map(\.name), ["HRV", "Resting HR", "Sleep"])
        XCTAssertNil(HealthInsights.stress(hrv: 60, hrvBaseline: [60], restingHR: nil, rhrBaseline: [],
                                           sleepHours: nil, respiratory: nil, respBaseline: []))
    }

    // MARK: - Illness watch

    func testIllnessCheckEscalatesWithSignalsMovingTogether() throws {
        let rhr = [56.0, 57, 56, 58, 57]
        let hrv = [62.0, 60, 64, 61, 63]
        let resp = [14.5, 14.8, 14.6, 14.7, 14.5]
        let temp = [0.0, 0.1, -0.1, 0.05, 0.0]
        let o2 = [97.0, 97, 96, 97, 97]
        func check(rhr r: Double, hrv h: Double, resp b: Double, temp t: Double?) -> HealthInsights.IllnessCheck? {
            HealthInsights.illnessCheck(restingHR: r, rhrBaseline: rhr, hrv: h, hrvBaseline: hrv,
                                        respiratory: b, respBaseline: resp, skinTemp: t, skinTempBaseline: temp,
                                        spO2: 97, spO2Baseline: o2)
        }
        XCTAssertEqual(try XCTUnwrap(check(rhr: 57, hrv: 61, resp: 14.6, temp: 0.1)).level, .clear)
        XCTAssertEqual(try XCTUnwrap(check(rhr: 62, hrv: 48, resp: 14.6, temp: 0.1)).level, .watch)
        XCTAssertEqual(try XCTUnwrap(check(rhr: 62, hrv: 61, resp: 14.6, temp: 0.9)).level, .alert, "Fever-like temp + one more")
        let sick = try XCTUnwrap(check(rhr: 63, hrv: 47, resp: 16.5, temp: nil))
        XCTAssertEqual(sick.level, .alert)
        XCTAssertEqual(sick.flaggedCount, 3)
        // HR up + HRV down after a short night reads as the night, not a cold.
        func withSleep(_ hours: Double?) -> HealthInsights.IllnessCheck? {
            HealthInsights.illnessCheck(restingHR: 62, rhrBaseline: rhr, hrv: 40, hrvBaseline: hrv,
                                        respiratory: 14.6, respBaseline: resp, skinTemp: 0.1, skinTempBaseline: temp,
                                        spO2: 97, spO2Baseline: o2, sleepHours: hours)
        }
        let shortNight = try XCTUnwrap(withSleep(4.9))
        XCTAssertEqual(shortNight.level, .watch)
        XCTAssertTrue(shortNight.likelyShortSleep)
        XCTAssertEqual(shortNight.headline, "A short night is showing")
        XCTAssertEqual(shortNight.baselineNights, 5)
        XCTAssertFalse(try XCTUnwrap(withSleep(7.5)).likelyShortSleep)
        let hrvSignal = try XCTUnwrap(shortNight.signals.first { $0.name == "HRV" })
        XCTAssertEqual(hrvSignal.change, "−35%")
        XCTAssertEqual(hrvSignal.history, hrv)
        XCTAssertEqual(hrvSignal.current, 40)
        XCTAssertTrue(try XCTUnwrap(hrvSignal.normal).contains(62))
        XCTAssertEqual(shortNight.signals.first { $0.name == "Resting heart rate" }?.change, "+5 bpm")

        // Too little history → no verdict.
        XCTAssertNil(HealthInsights.illnessCheck(restingHR: 70, rhrBaseline: [56, 57], hrv: 30, hrvBaseline: [60, 61],
                                                 respiratory: nil, respBaseline: [], skinTemp: nil, skinTempBaseline: [],
                                                 spO2: nil, spO2Baseline: []))
    }
}
