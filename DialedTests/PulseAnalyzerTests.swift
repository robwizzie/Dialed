//
//  PulseAnalyzerTests.swift
//  DialedTests
//
//  Jump scares found against a rolling baseline, marks matched to them,
//  scores, calm sessions and the leaderboard order.
//

import XCTest
@testable import Dialed

final class PulseAnalyzerTests: XCTestCase {

    private typealias S = PulseAnalyzer.Sample

    /// 100 minutes, a reading every 15 s around 72 bpm, with scares at
    /// 30:00 (+25), 70:00 (+30) and 85:00 (+15).
    private var movie: [S] {
        (0..<400).map { i in
            let t = Double(i) * 15
            var bpm = 72 + Double((i * 7) % 5) - 2
            if (1800..<1845).contains(t) { bpm = 97 }
            if (4200..<4245).contains(t) { bpm = 102 }
            if (5100..<5130).contains(t) { bpm = 87 }
            return S(t: t, bpm: bpm)
        }
    }

    func testFindsTheScaresAndMatchesYourMarks() {
        let r = PulseAnalyzer.analyze(movie, duration: 6000, marks: [4220, 3000])
        XCTAssertEqual(r.moments.map(\.t), [1800, 4200, 5100])
        XCTAssertEqual(r.moments.map(\.delta), [25, 30, 15])
        XCTAssertEqual(r.moments.map(\.marked), [false, true, false])
        XCTAssertEqual(r.biggest?.t, 4200)
        XCTAssertEqual(r.unmatchedMarks, [3000])
        XCTAssertEqual(r.baseline, 72)
        XCTAssertEqual(r.peak, 102)
        XCTAssertGreaterThan(r.moments[1].confidence, r.moments[0].confidence)
        XCTAssertEqual(r.score, 40)
    }

    func testCalmSessionsScoreTheDip() {
        let calm: [S] = (0..<80).map { i in S(t: Double(i) * 15, bpm: i < 20 ? 74 : max(60, 74 - Double(i - 20) * 0.4)) }
        let r = PulseAnalyzer.analyze(calm, duration: 1200, direction: .dip)
        XCTAssertGreaterThan(r.score, 70)
    }

    func testNoDataIsHonest() {
        let r = PulseAnalyzer.analyze([], duration: 3600, marks: [60])
        XCTAssertFalse(r.hasData)
        XCTAssertEqual(r.unmatchedMarks, [60])
    }

    func testLeaderboardAndClock() {
        let order = PulseAnalyzer.rank([.init(id: "a", score: 50, biggest: 20),
                                        .init(id: "b", score: 70, biggest: 10),
                                        .init(id: "c", score: 50, biggest: 30)])
        XCTAssertEqual(order, ["b", "c", "a"])
        XCTAssertEqual(PulseAnalyzer.clock(4350), "1:12:30")
        XCTAssertEqual(PulseAnalyzer.clock(750), "12:30")
        XCTAssertEqual(PulseTemplate.meditation.direction, .dip)
        XCTAssertEqual(PulseTemplate.scaryMovie.scoreName, "Scare score")
    }
}
