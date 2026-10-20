//
//  MetabolismEstimatorTests.swift
//  DialedTests
//
//  Measured burn from food + trend weight, compared with the formula for
//  your age, and the guards for thin or contradictory data.
//

import XCTest
@testable import Dialed

final class MetabolismEstimatorTests: XCTestCase {

    private typealias M = MetabolismEstimator
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let rob = MetabolismEstimator.Profile(age: 30, sex: .male, heightInches: 72, weightLbs: 206, bodyFat: 0.32)

    private func days(_ n: Int, eaten: Double?, active: Double?) -> [M.Day] {
        (0..<n).map { M.Day(date: base.addingTimeInterval(Double($0) * 86_400), eaten: eaten, active: active) }
    }

    func testFormulas() {
        XCTAssertEqual(M.mifflin(weightLbs: 206, heightInches: 72, age: 30, sex: .male), 1932.4, accuracy: 0.1)
        XCTAssertEqual(M.katchMcArdle(weightLbs: 206, bodyFat: 0.32), 1742.4, accuracy: 0.1)
        XCTAssertEqual(M.metabolicAge(rmr: 1932.4, weightLbs: 206, heightInches: 72, sex: .male), 30, accuracy: 0.1)
        XCTAssertEqual(M.metabolicAge(rmr: 1500, weightLbs: 206, heightInches: 72, sex: .male), 80)   // clamped
        XCTAssertEqual(M.speed(ratio: 1.08), .fast)
        XCTAssertEqual(M.speed(ratio: 0.92), .slow)
        XCTAssertEqual(M.speed(ratio: 1.0), .average)
    }

    func testMeasuredBurnFromFoodAndTrend() {
        // 2,200 a day, 600 active, 3 lb down over 20 days.
        let r = M.estimate(profile: rob, days: days(21, eaten: 2200, active: 600), trendStart: 209, trendEnd: 206)
        XCTAssertEqual(r.measuredTDEE, 2725)
        XCTAssertEqual(r.measuredRMR, 1905)
        XCTAssertEqual(r.speed, .average)
        XCTAssertEqual(r.metabolicAge, 35)
        XCTAssertEqual(r.ageDelta, 5)
        XCTAssertEqual(r.confidence, .high)
    }

    func testThinOrContradictoryData() {
        let unlogged = M.estimate(profile: rob, days: days(14, eaten: nil, active: 500), trendStart: 209, trendEnd: 208)
        XCTAssertEqual(unlogged.confidence, .insufficient)
        XCTAssertNil(unlogged.measuredTDEE)

        // 9 lb in two weeks on 1,000 calories is water and missed meals, not a fast metabolism.
        let odd = M.estimate(profile: rob, days: days(14, eaten: 1000, active: 500), trendStart: 215, trendEnd: 206)
        XCTAssertNil(odd.speed)
        XCTAssertEqual(odd.confidence, .low)

        let noAge = M.estimate(profile: M.Profile(age: nil, sex: nil, heightInches: 72, weightLbs: 206),
                               days: days(15, eaten: 2400, active: 500), trendStart: 208, trendEnd: 207)
        XCTAssertNotNil(noAge.measuredRMR)
        XCTAssertNil(noAge.speed)
    }
}
