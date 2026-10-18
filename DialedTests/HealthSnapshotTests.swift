//
//  HealthSnapshotTests.swift
//  DialedTests
//
//  The prompt text Apple Intelligence sees only states numbers we have,
//  and the no-AI trash-talk fallback always produces a message that
//  matches who's winning.
//

import XCTest
@testable import Dialed

final class HealthSnapshotTests: XCTestCase {

    private func challengeSnapshot(leader: WeightChallengeEngine.Leader) -> HealthSnapshot {
        var s = HealthSnapshot()
        s.firstName = "Rob"
        s.friendName = "Jake"
        s.challengeDay = 18
        s.challengeDays = 31
        s.daysLeft = 13
        s.scoring = .percent
        s.lostLbs = 4.6
        s.lostPercent = 2.4
        s.friendLostLbs = 3.4
        s.friendLostPercent = 1.9
        s.leader = leader
        s.margin = 0.5
        s.goalLossLbs = 8
        s.paceDelta = 0.2
        s.weight = 187.4
        s.weighedInToday = true
        s.waterOz = 64
        s.waterTargetOz = 120
        s.steps = 8_420
        s.proteinGrams = 132
        s.proteinTarget = 190
        s.caloriesIn = 1_480
        s.calorieTarget = 2_300
        s.sleepHours = 7.4
        return s
    }

    func testPromptIncludesChallengeAndDay() {
        let text = challengeSnapshot(leader: .you).promptText
        XCTAssertTrue(text.contains("vs. Jake: day 18 of 31"))
        XCTAssertTrue(text.contains("You lead by 0.5%"))
        XCTAssertTrue(text.contains("You've lost 4.6 lb (2.4%)"))
        XCTAssertTrue(text.contains("Water: 64 of 120 oz"))
        XCTAssertTrue(text.contains("Weight: 187.4 lb (weighed in today)"))
        XCTAssertTrue(text.contains("0.2 lb ahead of goal pace"))
    }

    func testPromptOmitsUnknownNumbers() {
        var s = HealthSnapshot()
        s.steps = 1_200
        let text = s.promptText
        XCTAssertFalse(text.contains("challenge"))
        XCTAssertFalse(text.contains("Weight:"))
        XCTAssertFalse(text.contains("sleep"))
        XCTAssertFalse(text.contains("Water:"))
        XCTAssertTrue(text.contains("Steps: 1200 of 10000"))
    }

    func testFallbackTrashTalkMatchesLeader() {
        for tone in TrashTalkTone.allCases {
            for variant in 0..<3 {
                let leading = DialedAIFallback.trashTalk(challengeSnapshot(leader: .you), tone: tone, variant: variant)
                let trailing = DialedAIFallback.trashTalk(challengeSnapshot(leader: .friend), tone: tone, variant: variant)
                XCTAssertFalse(leading.isEmpty)
                XCTAssertFalse(trailing.isEmpty)
                XCTAssertNotEqual(leading, trailing)
                XCTAssertTrue(leading.contains("0.5%") || leading.contains("13 days"), leading)
            }
        }
    }

    func testFallbackHandlesTie() {
        let text = DialedAIFallback.trashTalk(challengeSnapshot(leader: .tied), tone: .savage)
        XCTAssertFalse(text.isEmpty)
    }
}
