//
//  ChallengeSyncModelsTests.swift
//  DialedTests
//
//  Live challenge wire mapping: one upload per day inside the window,
//  the other side's weigh-ins come back as friend weigh-ins.
//

import XCTest
@testable import Dialed

final class ChallengeSyncModelsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private func at(_ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!
    }

    func testDayKeysRoundTrip() {
        XCTAssertEqual(ChallengeWire.dayKey(at(5, 9), calendar: calendar), "2026-10-05")
        XCTAssertEqual(ChallengeWire.date(fromKey: "2026-10-05", calendar: calendar), calendar.startOfDay(for: at(5, 9)))
        XCTAssertNil(ChallengeWire.date(fromKey: "nope", calendar: calendar))
    }

    func testUploadsKeepLastReadingPerDayInsideWindow() {
        let readings: [(date: Date, pounds: Double)] = [
            (at(18, 7), 215.0),            // before start
            (at(19, 7), 214.24), (at(19, 21), 215.1),
            (at(20, 7), 213.0)
        ]
        let up = ChallengeWire.uploads(from: readings, start: at(19, 0), end: at(30, 0), calendar: calendar)
        XCTAssertEqual(up.map(\.date), ["2026-10-19", "2026-10-20"])
        XCTAssertEqual(up.map(\.pounds), [215.1, 213.0])
    }

    func testMergeTakesOtherSide() throws {
        let json = """
        {"role":"owner","challenge":{"id":"abc","ownerName":"Rob","friendName":"Jake","startDate":"2026-10-19","endDate":"2026-11-19","ownerStart":214.2,"friendStart":null},
         "weighins":[{"role":"owner","date":"2026-10-19","pounds":214.2},{"role":"friend","date":"2026-10-19","pounds":190},{"role":"friend","date":"2026-10-21","pounds":188.4}],
         "messages":[{"id":1,"role":"friend","text":"catch me","createdAt":"2026-10-19T17:50:15Z"}]}
        """
        let state = try JSONDecoder().decode(ChallengeWire.State.self, from: Data(json.utf8))
        var local = WeightChallenge.makeDefault(now: at(19, 8), calendar: calendar)
        local.friendWeighIns = [.init(date: at(18, 9), pounds: 999)]
        let merged = ChallengeWire.merge(state, into: local, calendar: calendar)
        XCTAssertEqual(merged.friendWeighIns.map(\.pounds), [190, 188.4])
        XCTAssertEqual(merged.friendStartWeight, 190)
        XCTAssertEqual(state.messages.first?.text, "catch me")
        // A second sync with nothing new changes nothing.
        XCTAssertEqual(ChallengeWire.merge(state, into: merged, calendar: calendar), merged)
    }

    func testWorkoutCountsThisWeekAndTotal() {
        // Wed Oct 21 2026; week starts Mon Oct 19.
        let now = at(21, 18)
        let counts = ChallengeWire.workoutCounts(doneDays: ["2026-10-16", "2026-10-19", "2026-10-21", "2026-10-21"],
                                                 now: now, calendar: calendar)
        XCTAssertEqual(counts.week, 2)  // a day logged twice counts once
        XCTAssertEqual(counts.total, 3)
    }
}
