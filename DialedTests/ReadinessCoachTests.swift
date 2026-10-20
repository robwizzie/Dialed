//
//  ReadinessCoachTests.swift
//  DialedTests
//
//  Low readiness becomes recovery, Steady swaps heavy lifting for
//  intervals, 70s train as planned, 80+ picks the PR attempt.
//

import XCTest
@testable import Dialed

final class ReadinessCoachTests: XCTestCase {

    private func best(_ name: String, _ weight: Double, _ reps: Int) -> StrengthMilestones.Best {
        let set = StrengthMilestones.SetRecord(exercise: name, date: Date(timeIntervalSince1970: 0), weight: weight, reps: reps)
        return StrengthMilestones.bests([set])[name]!
    }

    private func inputs(_ readiness: Int?, session: WorkoutProgram.Session = WorkoutProgram.strengthA,
                        illness: Bool = false, hard: Int = 0,
                        bests: [String: StrengthMilestones.Best] = [:]) -> ReadinessCoach.Inputs {
        ReadinessCoach.Inputs(readiness: readiness, illnessWatch: illness, sleepScore: nil,
                              session: session, recentHardDays: hard, bests: bests)
    }

    func testNoReadinessNoAdvice() {
        XCTAssertNil(ReadinessCoach.recommend(inputs(nil)))
    }

    func testLowOrSickMeansRecovery() {
        let low = ReadinessCoach.recommend(inputs(40))!
        XCTAssertEqual(low.mode, .recovery)
        XCTAssertEqual(low.swap?.title, ReadinessCoach.recoverySession.title)
        let sick = ReadinessCoach.recommend(inputs(85, illness: true))!
        XCTAssertEqual(sick.mode, .recovery)
        XCTAssertEqual(sick.reasons.first, "Illness watch is on")
        // An easy day stays as it is.
        XCTAssertNil(ReadinessCoach.recommend(inputs(40, session: WorkoutProgram.rest))!.swap)
    }

    func testSteadySwapsHeavyLiftingForIntervals() {
        let r = ReadinessCoach.recommend(inputs(63))!
        XCTAssertEqual(r.mode, .lighter)
        XCTAssertEqual(r.swap?.kind, .bike)
        XCTAssertEqual(r.reasons.first, "Readiness 63 · Steady")
        // A bike day on a Steady morning holds.
        XCTAssertEqual(ReadinessCoach.recommend(inputs(63, session: WorkoutProgram.bike(week: 1, withLongWalk: false)))!.mode, .asPlanned)
        // Three hard days in a row tip a 75 into lighter.
        XCTAssertEqual(ReadinessCoach.recommend(inputs(75, hard: 3))!.mode, .lighter)
        XCTAssertEqual(ReadinessCoach.recommend(inputs(75))!.mode, .asPlanned)
    }

    func testPrimedPicksTheLiftsClosestToAMilestone() {
        let bests = ["Bench press": best("Bench press", 180, 6),               // 5 lb from 185
                     "Barbell back squat": best("Barbell back squat", 150, 8), // 5 lb from 155
                     "Cable fly": best("Cable fly", 40, 12)]                   // 10 lb from 50
        let r = ReadinessCoach.recommend(inputs(84, bests: bests))!
        XCTAssertEqual(r.mode, .prAttempt)
        XCTAssertEqual(r.attempts.map(\.exercise), ["Bench press", "Barbell back squat"])
        XCTAssertEqual(r.attempts[0].weight, 185)
        XCTAssertEqual(r.attempts[0].reps, 6)
        XCTAssertTrue(r.attempts[0].warmUp.hasPrefix("Warm up: 95 × 8"))
        // No history: primed but nothing to aim at.
        XCTAssertEqual(ReadinessCoach.recommend(inputs(84))!.mode, .asPlanned)
    }
}
