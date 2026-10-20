//
//  ActivityReviewTests.swift
//  DialedTests
//
//  Reviewing a stretch: time in each effort zone (gaps aren't invented
//  effort), and the resting / active lines it was judged against.
//

import XCTest
@testable import Dialed

final class ActivityReviewTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testZonesSplitTheStretch() {
        // Resting 60, max 185 → reserve 125. 10 min at 100 (32 %, easy),
        // 10 at 130 (56 %, moderate), 10 at 150 (72 %, hard), one reading a minute.
        let samples = (0..<30).map { m -> ActiveBouts.Sample in
            let bpm: Double = m < 10 ? 100 : m < 20 ? 130 : 150
            return .init(date: base.addingTimeInterval(Double(m) * 60), bpm: bpm)
        }
        let zones = ActivityReview.zones(samples, from: base, to: base.addingTimeInterval(30 * 60), resting: 60)
        XCTAssertEqual(zones.map(\.name), ["Easy", "Moderate", "Hard", "Peak"])
        XCTAssertEqual(zones[0].minutes, 10, accuracy: 0.01)
        XCTAssertEqual(zones[1].minutes, 10, accuracy: 0.01)
        XCTAssertEqual(zones[2].minutes, 10, accuracy: 0.01)
        XCTAssertEqual(zones[3].minutes, 0, accuracy: 0.01)
    }

    func testGapsAreCapped() {
        let samples = [ActiveBouts.Sample(date: base, bpm: 150),
                       ActiveBouts.Sample(date: base.addingTimeInterval(20 * 60), bpm: 150)]
        let zones = ActivityReview.zones(samples, from: base, to: base.addingTimeInterval(20 * 60), resting: 60)
        // 20 minutes apart, but only 2 count for the first reading.
        XCTAssertEqual(zones.reduce(0) { $0 + $1.minutes }, 2, accuracy: 0.01)
    }

    func testRestingRecoveredFromEffort() {
        // avg 122.5 at half the reserve with max 185 → resting 60.
        let resting = ActivityReview.resting(average: 122.5, effort: 0.5)
        XCTAssertEqual(resting, 60, accuracy: 0.01)
        XCTAssertEqual(ActivityReview.activeLine(resting: 60), 110, accuracy: 0.01)
    }

    func testSummary() {
        let samples = [ActiveBouts.Sample(date: base, bpm: 100), ActiveBouts.Sample(date: base.addingTimeInterval(60), bpm: 140)]
        let s = ActivityReview.summary(samples, from: base, to: base.addingTimeInterval(60))
        XCTAssertEqual(s?.average, 120)
        XCTAssertEqual(s?.peak, 140)
        XCTAssertNil(ActivityReview.summary(samples, from: base.addingTimeInterval(600), to: base.addingTimeInterval(700)))
    }
}
