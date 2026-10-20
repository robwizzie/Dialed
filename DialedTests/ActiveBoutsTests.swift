//
//  ActiveBoutsTests.swift
//  DialedTests
//
//  An hour of pickleball shows up from heart rate alone; a short spike,
//  a recorded workout and a resting day don't.
//

import XCTest
@testable import Dialed

final class ActiveBoutsTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// 8 hours, one reading a minute, resting in the 60s, with:
    /// pickleball 2:00–3:00 (125–150, dipping to 100 between points),
    /// a 3-minute spike at 4:10 and a recorded 40-minute workout at 5:00.
    private var day: [ActiveBouts.Sample] {
        (0..<480).map { m in
            var bpm = 65.0 + Double(m % 7)
            if (120..<180).contains(m) { bpm = m % 5 == 0 ? 100 : 125 + Double(m % 25) }
            if (250..<253).contains(m) { bpm = 140 }
            if (300..<340).contains(m) { bpm = 130 }
            return .init(date: base.addingTimeInterval(Double(m) * 60), bpm: bpm)
        }
    }

    func testFindsTheGameNotTheSpikeOrTheWorkout() {
        let workout = DateInterval(start: base.addingTimeInterval(300 * 60), end: base.addingTimeInterval(340 * 60))
        let bouts = ActiveBouts.find(in: day, excluding: [workout], settings: .init(weightLbs: 206))
        XCTAssertEqual(bouts.count, 1)
        XCTAssertEqual(bouts[0].minutes, 58, accuracy: 2)
        XCTAssertEqual(bouts[0].averageBPM, 131, accuracy: 3)
        XCTAssertEqual(bouts[0].calories, 560, accuracy: 60)
        // Without the recorded workout it's a second bout.
        XCTAssertEqual(ActiveBouts.find(in: day).count, 2)
    }

    func testRestingDayHasNothing() {
        let calm = (0..<300).map { ActiveBouts.Sample(date: base.addingTimeInterval(Double($0) * 60), bpm: 60 + Double($0 % 15)) }
        XCTAssertTrue(ActiveBouts.find(in: calm).isEmpty)
    }

    func testUsualActivityIsSuggestedFirst() {
        let bout = ActiveBouts.find(in: day)[0]
        let weekAgo = bout.start.addingTimeInterval(-7 * 86_400)
        let history = [("Golf", bout.start.addingTimeInterval(-3 * 86_400 + 5 * 3600)), ("Pickleball", weekAgo)]
        XCTAssertEqual(ActiveBouts.suggestions(for: bout, history: history.map { (name: $0.0, start: $0.1) }).first, "Pickleball")
    }
}
