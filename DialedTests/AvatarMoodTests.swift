//
//  AvatarMoodTests.swift
//  DialedTests
//
//  Mood scoring is paced to the time of day, picks the right tier, and
//  surfaces the biggest gaps; goal-day projection follows the trend.
//

import XCTest
@testable import Dialed

final class AvatarMoodTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func at(hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    private func snapshot(hour: Int) -> HealthSnapshot {
        var s = HealthSnapshot()
        s.now = at(hour: hour)
        s.waterTargetOz = 120
        s.stepGoal = 10_000
        s.proteinTarget = 190
        s.calorieTarget = 2_300
        return s
    }

    func testPerfectDayIsOnFire() {
        var s = snapshot(hour: 21)
        s.waterOz = 120; s.steps = 10_000; s.proteinGrams = 190
        s.caloriesIn = 2_000; s.sleepHours = 7.5; s.weighedInToday = true
        let r = AvatarMood.read(s, calendar: calendar)
        XCTAssertEqual(r.score, 100)
        XCTAssertEqual(r.mood, .onFire)
        XCTAssertTrue(r.boosts.isEmpty)
    }

    func testMorningIsJudgedAgainstMorningPace() {
        // 10 AM: expected ≈ 21% of targets. 26 oz water, 2,200 steps,
        // 40 g protein is right on pace.
        var s = snapshot(hour: 10)
        s.waterOz = 26; s.steps = 2_200; s.proteinGrams = 40
        s.caloriesIn = 500; s.sleepHours = 7.2; s.weighedInToday = true
        let r = AvatarMood.read(s, calendar: calendar)
        XCTAssertGreaterThanOrEqual(r.score, 95)
    }

    func testRoughNightIsRunningOnEmptyWithBoosts() {
        var s = snapshot(hour: 21)
        s.waterOz = 2; s.steps = 4_900; s.proteinGrams = 33
        s.caloriesIn = 0; s.sleepHours = 5.2; s.weighedInToday = false
        let r = AvatarMood.read(s, calendar: calendar)
        XCTAssertEqual(r.mood, .runningOnEmpty)
        XCTAssertEqual(r.boosts.count, 2)
        XCTAssertEqual(r.boosts.first?.name, "Water")
    }

    func testOverBudgetCostsPoints() {
        var s = snapshot(hour: 21)
        s.caloriesIn = 2_300
        let within = AvatarMood.read(s, calendar: calendar).components.first { $0.name == "Calorie budget" }!
        s.caloriesIn = 2_760  // 20% over
        let over = AvatarMood.read(s, calendar: calendar).components.first { $0.name == "Calorie budget" }!
        XCTAssertEqual(within.points, 15)
        XCTAssertEqual(over.points, 3, accuracy: 0.01)
    }

    func testMoodTiers() {
        XCTAssertEqual(AvatarMood.from(score: 85), .onFire)
        XCTAssertEqual(AvatarMood.from(score: 60), .lockedIn)
        XCTAssertEqual(AvatarMood.from(score: 59), .gettingThere)
        XCTAssertEqual(AvatarMood.from(score: 12), .runningOnEmpty)
    }

    func testProjectionFollowsTrendToGoalDay() {
        let today = calendar.startOfDay(for: Date())
        let readings = (0..<14).map { i -> WeightReading in
            let day = calendar.date(byAdding: .day, value: -13 + i, to: today)!
            return WeightReading(date: calendar.date(byAdding: .hour, value: 7, to: day)!,
                                 pounds: 195 - Double(i) * 0.2, source: .manual)
        }
        let target = calendar.date(byAdding: .day, value: 31, to: today)!
        let p = WeightChallengeEngine.projection(readings: readings, to: target, now: Date(), calendar: calendar)
        XCTAssertNotNil(p)
        // Latest 192.4, losing 0.2/day → 31 more days ≈ 186.2
        XCTAssertEqual(p!.weight, 192.4 - 6.2, accuracy: 0.05)
        XCTAssertEqual(p!.weeklyRate, -1.4, accuracy: 0.01)
    }

    func testProjectionClampsWildTrends() {
        let today = calendar.startOfDay(for: Date())
        let readings = (0..<3).map { i -> WeightReading in
            WeightReading(date: calendar.date(byAdding: .day, value: -2 + i, to: today)!,
                          pounds: 200 - Double(i) * 3, source: .manual)   // 21 lb/week "trend"
        }
        let p = WeightChallengeEngine.projection(readings: readings, to: calendar.date(byAdding: .day, value: 28, to: today)!, calendar: calendar)
        XCTAssertEqual(p!.weeklyRate, -3, accuracy: 0.001)
    }

    func testGoalEventDaysAway() {
        let event = GoalEvent(name: "Wedding", date: calendar.date(byAdding: .day, value: 31, to: Date())!)
        XCTAssertEqual(event.daysAway(calendar: calendar), 31)
    }
}
