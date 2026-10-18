//
//  WeightChallengeEngineTests.swift
//  DialedTests
//
//  Daily collapsing, trend smoothing, pace, projection, head-to-head
//  scoring, streaks and cross-source de-duplication.
//

import XCTest
@testable import Dialed

final class WeightChallengeEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func day(_ offset: Int, hour: Int = 7, from base: Date) -> Date {
        let d = calendar.date(byAdding: .day, value: offset, to: base)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }

    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    }

    private func challenge(
        goal: Double = 8,
        scoring: WeightChallenge.Scoring = .percent,
        friendStart: Double? = nil,
        friend: [WeightChallenge.FriendWeighIn] = []
    ) -> WeightChallenge {
        WeightChallenge(
            friendName: "Jake",
            startDate: start,
            endDate: calendar.date(byAdding: .day, value: 30, to: start)!,
            startWeightOverride: nil,
            goalLossLbs: goal,
            friendStartWeight: friendStart,
            friendWeighIns: friend,
            scoring: scoring
        )
    }

    // MARK: - Daily series

    func testDailySeriesKeepsEarliestReadingPerDay() {
        let readings = [
            WeightReading(date: day(0, hour: 21, from: start), pounds: 192, source: .healthKit),
            WeightReading(date: day(0, hour: 7, from: start), pounds: 190, source: .healthKit),
            WeightReading(date: day(1, hour: 7, from: start), pounds: 189.6, source: .fitbit)
        ]
        let series = WeightChallengeEngine.dailySeries(readings, calendar: calendar)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].pounds, 190)
        XCTAssertEqual(series[1].pounds, 189.6)
    }

    func testTrendIsSmoothed() {
        let readings = [
            WeightReading(date: day(0, from: start), pounds: 190, source: .manual),
            WeightReading(date: day(1, from: start), pounds: 194, source: .manual)
        ]
        let series = WeightChallengeEngine.dailySeries(readings, calendar: calendar, smoothing: 0.25)
        XCTAssertEqual(series[0].trend, 190)
        XCTAssertEqual(series[1].trend, 191, accuracy: 0.0001)
    }

    // MARK: - Progress

    func testProgressMidChallenge() {
        // Steady 0.25 lb/day loss for 10 days: 190 → 187.75
        let readings = (0...9).map {
            WeightReading(date: day($0, from: start), pounds: 190 - Double($0) * 0.25, source: .healthKit)
        }
        let now = day(9, hour: 12, from: start)
        let p = WeightChallengeEngine.progress(challenge: challenge(), readings: readings, now: now, calendar: calendar)

        XCTAssertEqual(p.startWeight, 190)
        XCTAssertEqual(p.currentWeight ?? 0, 187.75, accuracy: 0.001)
        XCTAssertEqual(p.lostLbs, 2.25, accuracy: 0.001)
        XCTAssertEqual(p.lostPercent, 2.25 / 190 * 100, accuracy: 0.001)
        XCTAssertEqual(p.dayNumber, 10)
        XCTAssertEqual(p.totalDays, 30)
        XCTAssertEqual(p.daysLeft, 21)
        // Expected by day 9 of 30 at 8 lb goal = 2.4
        XCTAssertEqual(p.expectedLossByNow, 8 * 9.0 / 30, accuracy: 0.001)
        XCTAssertEqual(p.paceDelta, 2.25 - 2.4, accuracy: 0.001)
        // Line through 0.25 lb/day lands at 190 − 0.25 × 30 = 182.5 on day 30.
        XCTAssertEqual(p.projectedLossAtEnd ?? 0, 7.5, accuracy: 0.001)
        XCTAssertEqual(p.weeklyRate ?? 0, 1.75, accuracy: 0.001)
        // Remaining 5.75 lb over 21 days
        XCTAssertEqual(p.requiredDailyDeficit, 5.75 * 3500 / 21, accuracy: 0.5)
        XCTAssertTrue(p.weighedInToday)
        XCTAssertEqual(p.weighInStreak, 10)
    }

    func testStartWeightFallsBackToLastReadingBeforeStart() {
        let readings = [
            WeightReading(date: day(-2, from: start), pounds: 195, source: .healthKit),
            WeightReading(date: day(3, from: start), pounds: 193, source: .healthKit)
        ]
        // First reading on/after start wins over the earlier one.
        let p = WeightChallengeEngine.progress(challenge: challenge(), readings: readings, now: day(3, from: start), calendar: calendar)
        XCTAssertEqual(p.startWeight, 193)

        var c = challenge()
        c.startWeightOverride = 196
        let p2 = WeightChallengeEngine.progress(challenge: c, readings: readings, now: day(3, from: start), calendar: calendar)
        XCTAssertEqual(p2.startWeight, 196)
        XCTAssertEqual(p2.lostLbs, 3, accuracy: 0.001)
    }

    func testRequiredDeficitIsZeroOnceGoalHit() {
        let readings = [
            WeightReading(date: day(0, from: start), pounds: 200, source: .manual),
            WeightReading(date: day(5, from: start), pounds: 190, source: .manual)
        ]
        let p = WeightChallengeEngine.progress(challenge: challenge(goal: 8), readings: readings, now: day(5, from: start), calendar: calendar)
        XCTAssertEqual(p.requiredDailyDeficit, 0)
        XCTAssertEqual(p.goalProgress, 1)
    }

    // MARK: - Head to head

    func testPercentScoringFavorsLighterPersonWithSameLbs() {
        // You: 200 → 196 (4 lb, 2.0%). Jake: 160 → 156 (4 lb, 2.5%).
        let readings = [
            WeightReading(date: day(0, from: start), pounds: 200, source: .manual),
            WeightReading(date: day(5, from: start), pounds: 196, source: .manual)
        ]
        let friend = [WeightChallenge.FriendWeighIn(date: day(5, from: start), pounds: 156)]
        let p = WeightChallengeEngine.progress(
            challenge: challenge(scoring: .percent, friendStart: 160, friend: friend),
            readings: readings, now: day(5, from: start), calendar: calendar
        )
        XCTAssertEqual(p.leader, .friend)
        XCTAssertEqual(p.margin, 0.5, accuracy: 0.001)

        let byPounds = WeightChallengeEngine.progress(
            challenge: challenge(scoring: .pounds, friendStart: 160, friend: friend),
            readings: readings, now: day(5, from: start), calendar: calendar
        )
        XCTAssertEqual(byPounds.leader, .tied)
    }

    func testFriendStartDefaultsToFirstWeighIn() {
        let friend = [
            WeightChallenge.FriendWeighIn(date: day(0, from: start), pounds: 180),
            WeightChallenge.FriendWeighIn(date: day(7, from: start), pounds: 177)
        ]
        let fp = WeightChallengeEngine.friendProgress(challenge: challenge(friend: friend))
        XCTAssertEqual(fp?.startWeight, 180)
        XCTAssertEqual(fp?.lostLbs ?? 0, 3, accuracy: 0.001)
    }

    func testLeaderUnknownWithoutFriendData() {
        let readings = [WeightReading(date: day(0, from: start), pounds: 190, source: .manual)]
        let p = WeightChallengeEngine.progress(challenge: challenge(), readings: readings, now: day(0, from: start), calendar: calendar)
        XCTAssertEqual(p.leader, .unknown)
    }

    // MARK: - Streak

    func testStreakSurvivesNotYetWeighedInToday() {
        let readings = (0...3).map { WeightReading(date: day($0, from: start), pounds: 190, source: .manual) }
        let series = WeightChallengeEngine.dailySeries(readings, calendar: calendar)
        let today = calendar.startOfDay(for: day(4, from: start))
        XCTAssertEqual(WeightChallengeEngine.streak(series, today: today, calendar: calendar), 4)
        let dayAfter = calendar.startOfDay(for: day(5, from: start))
        XCTAssertEqual(WeightChallengeEngine.streak(series, today: dayAfter, calendar: calendar), 0)
    }

    // MARK: - Merge

    func testMergeDropsSameWeighInReportedByTwoSources() {
        let t = day(0, from: start)
        let merged = WeightChallengeEngine.merge([
            [WeightReading(date: t, pounds: 190.2, source: .healthKit)],
            [WeightReading(date: t.addingTimeInterval(120), pounds: 190.1, source: .fitbit)],
            [WeightReading(date: t.addingTimeInterval(3600 * 5), pounds: 191, source: .manual)]
        ])
        XCTAssertEqual(merged.count, 2)
    }
}
