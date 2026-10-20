//
//  HeadToHeadTests.swift
//  DialedTests
//
//  "Dave just weighed in" says the right thing, only new weigh-ins count,
//  and trash-talk nudges stay rare and daytime.
//

import XCTest
@testable import Dialed

final class HeadToHeadTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func challenge(friend: [(Int, Double)]) -> WeightChallenge {
        var c = WeightChallenge.makeDefault(now: at(1, 9), calendar: calendar)
        c.friendName = "Dave"
        c.scoring = .pounds
        c.friendStartWeight = 220
        c.friendWeighIns = friend.map { .init(date: at($0.0, 12), pounds: $0.1) }
        return c
    }

    private func progress(_ c: WeightChallenge, you: Double) -> WeightChallengeEngine.Progress {
        let readings = [WeightReading(date: at(1, 7), pounds: 210, source: .manual),
                        WeightReading(date: at(20, 7), pounds: you, source: .manual)]
        return WeightChallengeEngine.progress(challenge: c, readings: readings, now: at(20, 18), calendar: calendar)
    }

    func testOnlyNewWeighInsCount() {
        let c = challenge(friend: [(10, 218), (20, 217.2)])
        let before = HeadToHead.Snapshot(leader: "you", friendKeys: [HeadToHead.key(c.friendWeighIns[0], calendar: calendar)], yourStreak: 1)
        XCTAssertEqual(HeadToHead.newWeighIns(c.friendWeighIns, since: before, calendar: calendar).map(\.pounds), [217.2])
        XCTAssertTrue(HeadToHead.newWeighIns(c.friendWeighIns, since: nil, calendar: calendar).isEmpty)
    }

    func testAlertFramesTheScoreboard() {
        let c = challenge(friend: [(10, 218), (20, 217.2)])
        let ahead = progress(c, you: 205)   // you −5, Dave −2.8
        let alert = HeadToHead.weighInAlert(friendName: "Dave", scoring: .pounds, progress: ahead, previousLeader: "you",
                                            newest: c.friendWeighIns[1], prior: c.friendWeighIns[0])
        XCTAssertEqual(alert.title, "Dave just weighed in")
        XCTAssertEqual(alert.body, "Dave −0.8 lb since their last weigh-in. You're still ahead by 2.2 lb.")

        let behind = progress(c, you: 208.6) // you −1.4
        let flipped = HeadToHead.weighInAlert(friendName: "Dave", scoring: .pounds, progress: behind, previousLeader: "you",
                                              newest: c.friendWeighIns[1], prior: c.friendWeighIns[0])
        XCTAssertEqual(flipped.body, "Dave −0.8 lb since their last weigh-in. Dave took the lead by 1.4 lb. Time to answer.")
    }

    func testNudgeReasons() {
        let before = HeadToHead.Snapshot(leader: "you", friendKeys: [], yourStreak: 6)
        XCTAssertEqual(HeadToHead.nudgeReason(before: before, after: .init(leader: "friend", friendKeys: [], yourStreak: 6),
                                              newest: nil, prior: nil), .lostLead)
        XCTAssertEqual(HeadToHead.nudgeReason(before: before, after: .init(leader: "you", friendKeys: [], yourStreak: 7),
                                              newest: nil, prior: nil), .streak(7))
        let drop = HeadToHead.nudgeReason(before: before, after: before,
                                          newest: .init(date: at(20, 12), pounds: 215), prior: .init(date: at(18, 12), pounds: 217))
        XCTAssertEqual(drop, .friendBigDrop)
        XCTAssertNil(HeadToHead.nudgeReason(before: nil, after: before, newest: nil, prior: nil))
    }

    func testNudgesStayRareAndDaytime() {
        XCTAssertEqual(HeadToHead.nudgeTime(now: at(20, 14), sent: [], calendar: calendar), at(20, 14))
        // 10 PM → 8:05 tomorrow
        XCTAssertEqual(HeadToHead.nudgeTime(now: at(20, 22), sent: [], calendar: calendar),
                       calendar.date(bySettingHour: 8, minute: 5, second: 0, of: at(21, 0)))
        // too soon after the last, and two this week already
        XCTAssertNil(HeadToHead.nudgeTime(now: at(20, 14), sent: [at(19, 14)], calendar: calendar))
        XCTAssertNil(HeadToHead.nudgeTime(now: at(20, 14), sent: [at(14, 12), at(17, 12)], calendar: calendar))
    }
}
