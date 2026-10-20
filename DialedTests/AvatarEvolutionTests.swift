//
//  AvatarEvolutionTests.swift
//  DialedTests
//
//  The avatar's stage follows trend weight toward the goal, glows with
//  streaks, and only ever levels up.
//

import XCTest
@testable import Dialed

final class AvatarEvolutionTests: XCTestCase {

    private func read(_ trend: Double, streak: Int = 0) -> AvatarEvolution.Reading {
        AvatarEvolution.read(.init(startWeight: 210, goalWeight: 190, trendWeight: trend, streakDays: streak))
    }

    func testStagesFollowProgress() {
        XCTAssertEqual(read(210).stage.level, 1)
        XCTAssertEqual(read(206).stage.level, 2)     // 20 %
        XCTAssertEqual(read(202).stage.level, 3)     // 40 %
        XCTAssertEqual(read(199).stage.level, 4)     // 55 %
        XCTAssertEqual(read(193.5).stage.level, 5)   // 82.5 %
        XCTAssertEqual(read(190).stage.level, 6)
        XCTAssertNil(read(190).next)
        XCTAssertEqual(read(212).progress, 0)        // up from the start isn't negative
    }

    func testDistanceToNextStage() {
        let r = read(210)
        XCTAssertEqual(r.lbsToNext ?? 0, 3, accuracy: 0.01)   // 15 % of 20 lb
        XCTAssertEqual(read(206).toNext, 0.25, accuracy: 0.01)
    }

    func testGlowFromStreaks() {
        XCTAssertEqual(read(205, streak: 2).glow, 0)
        XCTAssertEqual(read(205, streak: 3).glow, 1)
        XCTAssertEqual(read(205, streak: 7).glow, 2)
        XCTAssertEqual(read(205, streak: 30).glow, 3)
    }

    func testOnlyEverLevelsUp() {
        XCTAssertEqual(AvatarEvolution.settle(stored: nil, reached: 3).level, 3)
        XCTAssertFalse(AvatarEvolution.settle(stored: nil, reached: 3).leveledUp)   // first reading: no party
        XCTAssertEqual(AvatarEvolution.settle(stored: 3, reached: 2).level, 3)      // a heavy week keeps the level
        XCTAssertTrue(AvatarEvolution.settle(stored: 3, reached: 4).leveledUp)
    }

    func testPromptsStayPositive() {
        for stage in AvatarEvolution.stages {
            for word in ["fat", "overweight", "chubby", "obese"] {
                XCTAssertFalse(stage.prompt.lowercased().contains(word), "\(stage.name) prompt mentions \(word)")
            }
        }
    }
}
