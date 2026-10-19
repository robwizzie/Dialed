//
//  WeeklyReviewTests.swift
//  DialedTests
//
//  Week selection, averages and on-target counts, best / worst day,
//  weight trend across the week, and the deterministic "one thing to fix".
//

import XCTest
@testable import Dialed

final class WeeklyReviewTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func day(_ d: Int, month: Int = 10, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
    }

    private let targets = WeeklyReview.Targets(calories: 2_200, protein: 190, waterOz: 120)

    /// Mon Oct 12 → Sun Oct 18, 2026.
    private func goodWeek() -> [WeeklyReview.Day] {
        (12...18).map { d in
            WeeklyReview.Day(date: day(d), caloriesIn: 2_000, proteinGrams: 190, waterOz: 120,
                             steps: 11_000, sleepHours: 7.5, weighedIn: true, workoutDone: d % 2 == 0)
        }
    }

    // MARK: - Week range

    func testWeekRangeOnMondayIsLastWeek() {
        let r = WeeklyReview.weekRange(now: day(19, hour: 9), calendar: calendar)   // Monday
        XCTAssertEqual(r.start, day(12))
        XCTAssertEqual(r.end, day(18))
    }

    func testWeekRangeOnSundayIsThisWeek() {
        let r = WeeklyReview.weekRange(now: day(25, hour: 18), calendar: calendar)  // Sunday
        XCTAssertEqual(r.start, day(19))
        XCTAssertEqual(r.end, day(25))
    }

    func testWeeksBack() {
        let r = WeeklyReview.weekRange(now: day(19, hour: 9), weeksBack: 2, calendar: calendar)
        XCTAssertEqual(r.start, day(28, month: 9))
        XCTAssertEqual(r.end, day(4))
        XCTAssertEqual(WeeklyReview.days(from: r.start, to: r.end, calendar: calendar).count, 7)
    }

    // MARK: - Summary

    func testAveragesAndOnTargetCounts() {
        var days = goodWeek()
        days[0].caloriesIn = 2_600       // over budget
        days[1].proteinGrams = 120       // under protein
        days[2].waterOz = 60             // under water
        days[3].steps = 5_000            // under steps
        days[4].sleepHours = 6           // short night
        days[5].weighedIn = false
        let s = WeeklyReview.summarize(days: days, readings: [], targets: targets,
                                       start: day(12), end: day(18), calendar: calendar)
        XCTAssertEqual(s.days.count, 7)
        XCTAssertEqual(s.calorieDays, 6)
        XCTAssertEqual(s.proteinDays, 6)
        XCTAssertEqual(s.waterDays, 6)
        XCTAssertEqual(s.stepDays, 6)
        XCTAssertEqual(s.sleepDays, 6)
        XCTAssertEqual(s.weighInDays, 6)
        XCTAssertEqual(s.workoutsDone, 4)   // 12, 14, 16, 18
        XCTAssertEqual(s.avgCalories ?? 0, (2_000 * 6 + 2_600) / 7, accuracy: 0.01)
        XCTAssertEqual(s.avgProtein ?? 0, (190 * 6 + 120) / 7, accuracy: 0.01)
    }

    func testDaysOutsideTheWeekAreIgnored() {
        var days = goodWeek()
        days.append(WeeklyReview.Day(date: day(19), caloriesIn: 5_000))
        let s = WeeklyReview.summarize(days: days, readings: [], targets: targets,
                                       start: day(12), end: day(18), calendar: calendar)
        XCTAssertEqual(s.days.count, 7)
        XCTAssertEqual(s.avgCalories ?? 0, 2_000, accuracy: 0.01)
    }

    func testBestAndWorstDay() {
        var days = goodWeek()
        days[3] = WeeklyReview.Day(date: day(15), caloriesIn: 3_000, proteinGrams: 80, waterOz: 40, steps: 3_000, sleepHours: 5)
        days[6] = WeeklyReview.Day(date: day(18))      // nothing logged → excluded
        let s = WeeklyReview.summarize(days: days, readings: [], targets: targets,
                                       start: day(12), end: day(18), calendar: calendar)
        XCTAssertEqual(s.scores.count, 6)
        XCTAssertEqual(s.worst?.date, day(15))
        XCTAssertEqual(s.best?.score, 100)
        XCTAssertLessThan(s.worst?.score ?? 100, 40)
        XCTAssertNotNil(WeeklyReview.weakest(days[3], targets: targets, calendar: calendar))
        XCTAssertNil(WeeklyReview.weakest(days[0], targets: targets, calendar: calendar))
    }

    func testPerfectDayScoresLikeAvatarMood() {
        let d = goodWeek()[0]
        XCTAssertEqual(WeeklyReview.score(d, targets: targets, calendar: calendar), 100)
    }

    func testWeightTrendAcrossTheWeek() {
        // Steady 0.2 lb/day loss for four weeks before and through the week.
        let readings = (0..<35).map { i -> WeightReading in
            let date = calendar.date(byAdding: .day, value: i, to: day(14, month: 9, hour: 7))!
            return WeightReading(date: date, pounds: 220 - Double(i) * 0.2, source: .manual)
        }
        let s = WeeklyReview.summarize(days: goodWeek(), readings: readings, targets: targets,
                                       start: day(12), end: day(18), calendar: calendar)
        XCTAssertNotNil(s.weightChange)
        XCTAssertLessThan(s.weightChange ?? 0, -1.0)
        XCTAssertEqual(s.weeklyRate ?? 0, -1.4, accuracy: 0.35)
    }

    func testWorkoutKeys() {
        let keys = WeeklyReview.workoutKeys("2026-10-12, 2026-10-14,,2026-10-16")
        XCTAssertEqual(keys, ["2026-10-12", "2026-10-14", "2026-10-16"])
        XCTAssertEqual(WeeklyReview.dayKey(day(12), calendar: calendar), "2026-10-12")
    }

    // MARK: - One thing to fix

    private func summary(_ days: [WeeklyReview.Day]) -> WeeklyReview.Summary {
        WeeklyReview.summarize(days: days, readings: [], targets: targets, start: day(12), end: day(18), calendar: calendar)
    }

    func testGreatWeekHasNoFix() {
        XCTAssertEqual(WeeklyReview.biggestGap(summary(goodWeek()), targets: targets).area, .none)
    }

    func testBarelyLoggedFoodMeansLogMore() {
        var days = goodWeek()
        for i in 0..<5 { days[i].caloriesIn = nil }
        XCTAssertEqual(WeeklyReview.biggestGap(summary(days), targets: targets).area, .logging)
    }

    func testPicksTheBiggestGap() {
        var days = goodWeek()
        for i in 0..<5 { days[i].proteinGrams = 110 }   // protein missed 5 days → 20 × 5/7
        for i in 0..<4 { days[i].weighedIn = false }    // weigh-in missed 4 → 10 × 4/7
        let fix = WeeklyReview.biggestGap(summary(days), targets: targets)
        XCTAssertEqual(fix.area, .protein)
        XCTAssertTrue(fix.detail.contains("2 of 7"))
    }

    func testCaloriesWeightedBelowWaterOnTie() {
        var days = goodWeek()
        for i in 0..<4 {
            days[i].caloriesIn = 2_800   // calories missed 4 → 15 × 4/7 ≈ 8.6
            days[i].waterOz = 50         // water missed 4  → 20 × 4/7 ≈ 11.4
        }
        XCTAssertEqual(WeeklyReview.biggestGap(summary(days), targets: targets).area, .water)
    }

    func testStepsFixMentionsPeaches() {
        var days = goodWeek()
        for i in 0..<6 { days[i].steps = 4_000 }
        let fix = WeeklyReview.biggestGap(summary(days), targets: targets)
        XCTAssertEqual(fix.area, .steps)
        XCTAssertTrue(fix.headline.contains("Peaches"))
    }

    func testPromptTextHasTheNumbers() {
        let text = WeeklyReview.promptText(summary(goodWeek()), targets: targets, goalName: "Wedding", daysToGoal: 31)
        XCTAssertTrue(text.contains("Protein: avg 190 g vs 190 g, hit 7 of 7 days"))
        XCTAssertTrue(text.contains("Goal: Wedding in 31 days"))
    }
}
