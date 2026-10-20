//
//  RacePaceTests.swift
//  DialedTests
//
//  The pace you need to beat your friend, and a trend weight that copes
//  with long gaps between weigh-ins.
//

import XCTest
@testable import Dialed

final class RacePaceTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func day(_ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: m, day: d))! }

    private var inputs: RacePace.Inputs {
        RacePace.Inputs(scoring: .pounds, yourStart: 210, yourTrend: 206, yourTrendRate: 1.6, yourFoodRate: 1.2,
                        friendStart: 220, friendWeighIns: [(day(10, 1), 220), (day(10, 8), 218.5), (day(10, 15), 217)],
                        challengeStart: day(10, 1), end: day(11, 19), now: day(10, 20))
    }

    func testNeededPaceToFinishAhead() {
        let r = RacePace.compute(inputs, calendar: calendar)
        // Friend loses 1.5 lb/week → ~10.5 lb by Nov 19; you need 11 − 4 over ~4.3 weeks.
        XCTAssertEqual(r.friendProjectedLoss ?? 0, 10.5, accuracy: 0.1)
        XCTAssertEqual(r.needed, 1.63, accuracy: 0.02)
        XCTAssertEqual(r.status, .behind)

        var faster = inputs
        faster.yourTrendRate = 2.4
        XCTAssertEqual(RacePace.compute(faster, calendar: calendar).status, .ahead)
    }

    func testCaloriesAndFoodRate() {
        XCTAssertEqual(RacePace.calories(for: 1.63, weight: 206), 2270)
        XCTAssertEqual(RacePace.calories(for: 5, weight: 150), 1500)   // never below 1,500
        XCTAssertEqual(RacePace.foodRate(days: [(2000, 200), (1900, 0), (2200, 300)], weight: 206) ?? 0, 2.45, accuracy: 0.01)
        XCTAssertNil(RacePace.foodRate(days: [(2000, 0)], weight: 206))
    }

    func testTrendCatchesUpAfterALongGap() {
        let readings = [WeightReading(date: day(1, 22), pounds: 200.2, source: .manual),
                        WeightReading(date: day(10, 19), pounds: 206.5, source: .manual),
                        WeightReading(date: day(10, 20), pounds: 205.0, source: .manual)]
        let series = WeightChallengeEngine.dailySeries(readings, calendar: calendar)
        XCTAssertEqual(series[1].trend, 206.5, accuracy: 0.01)     // nine months later: the scale, not January
        XCTAssertEqual(series[2].trend, 206.125, accuracy: 0.01)   // next day: a quarter of the way
    }
}
