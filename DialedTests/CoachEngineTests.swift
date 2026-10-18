//
//  CoachEngineTests.swift
//  DialedTests
//
//  Coach nudges fire only when the data backs them up, and rank
//  most-urgent first.
//

import XCTest
@testable import Dialed

final class CoachEngineTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func at(hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    func testWaterBehindScheduleNudges() {
        var inputs = CoachEngine.Inputs()
        inputs.now = at(hour: 14)          // half way through the 7–21 window
        inputs.waterOz = 20
        inputs.waterTargetOz = 120         // expected ≈ 60
        inputs.steps = 10_000
        let insights = CoachEngine.insights(inputs, calendar: calendar, limit: 10)
        let water = insights.first { $0.id == "water" }
        XCTAssertNotNil(water)
        XCTAssertEqual(water?.tone, .nudge)
    }

    func testNoWaterNudgeEarlyInTheDay() {
        var inputs = CoachEngine.Inputs()
        inputs.now = at(hour: 6)
        inputs.waterOz = 0
        let insights = CoachEngine.insights(inputs, calendar: calendar, limit: 10)
        XCTAssertNil(insights.first { $0.id == "water" })
        XCTAssertNil(insights.first { $0.id == "steps" })
    }

    func testShortSleepFlagged() {
        var inputs = CoachEngine.Inputs()
        inputs.now = at(hour: 6)
        inputs.lastSleepHours = 5.2
        let insights = CoachEngine.insights(inputs, calendar: calendar, limit: 10)
        XCTAssertEqual(insights.first { $0.id == "sleep" }?.tone, .rest)
    }

    func testResultsAreRankedAndLimited() {
        var inputs = CoachEngine.Inputs()
        inputs.now = at(hour: 18)
        inputs.waterOz = 10
        inputs.steps = 1_000
        inputs.proteinGrams = 20
        inputs.lastSleepHours = 5
        let insights = CoachEngine.insights(inputs, calendar: calendar, limit: 3)
        XCTAssertEqual(insights.count, 3)
        XCTAssertEqual(insights.map(\.priority), insights.map(\.priority).sorted(by: >))
    }
}
