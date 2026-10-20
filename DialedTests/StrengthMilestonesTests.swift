//
//  StrengthMilestonesTests.swift
//  DialedTests
//
//  PRs from a finished session, and the next round number to chase.
//

import XCTest
@testable import Dialed

final class StrengthMilestonesTests: XCTestCase {

    typealias R = StrengthMilestones.SetRecord
    private let lastWeek = Date(timeIntervalSince1970: 1_800_000_000)
    private var today: Date { lastWeek.addingTimeInterval(7 * 86_400) }

    private var history: [R] {
        [R(exercise: "Bench press", date: lastWeek, weight: 135, reps: 10),
         R(exercise: "Bench press", date: lastWeek, weight: 145, reps: 8),
         R(exercise: "Incline bench press", date: lastWeek, weight: 110, reps: 10),
         R(exercise: "Pec deck fly", date: lastWeek, weight: 100, reps: 10)]
    }

    private var session: [R] {
        [R(exercise: "Bench press", date: today, weight: 155, reps: 8),
         R(exercise: "Incline bench press", date: today, weight: 100, reps: 12),
         R(exercise: "Pec deck fly", date: today, weight: 100, reps: 12),
         R(exercise: "Barbell back squat", date: today, weight: 225, reps: 5)]
    }

    func testPRs() {
        let prs = StrengthMilestones.prs(session: session, history: history)
        XCTAssertEqual(prs.map(\.exercise), ["Bench press", "Pec deck fly"])   // squat: first log; incline: lighter
        XCTAssertEqual(prs[0].kind, .heaviest)
        XCTAssertEqual(prs[0].text, "Bench press: heaviest ever, 155 × 8 (was 145)")
        XCTAssertEqual(prs[1].kind, .repsAtWeight)
        XCTAssertEqual(prs[1].text, "Pec deck fly: most reps at 100 lb, 12 (was 10)")
    }

    func testEstimatedMaxCapsReps() {
        XCTAssertEqual(StrengthMilestones.e1RM(weight: 100, reps: 20), StrengthMilestones.e1RM(weight: 100, reps: 12))
        XCTAssertEqual(StrengthMilestones.e1RM(weight: 155, reps: 8), 196.33, accuracy: 0.01)
        let more = [R(exercise: "Bench press", date: today, weight: 140, reps: 12)]
        let pr = StrengthMilestones.prs(session: more, history: history).first
        XCTAssertEqual(pr?.kind, .estimatedMax)   // 140 × 12 ≈ 196 beats 145 × 8 ≈ 184
    }

    func testNextMilestones() {
        let bests = StrengthMilestones.bests(history + session)
        let squat = StrengthMilestones.nextMilestone(for: bests["Barbell back squat"]!)!
        XCTAssertEqual(squat.target, 275)
        XCTAssertEqual(squat.text, "You're 50 lb from a 275 barbell back squat")
        let bench = StrengthMilestones.nextMilestone(for: bests["Bench press"]!)!
        XCTAssertEqual(bench.target, 185)
        XCTAssertTrue(bench.withinReach)   // est. max ~196
        let fly = StrengthMilestones.nextMilestone(for: bests["Pec deck fly"]!)!
        XCTAssertEqual(fly.text, "You're 5 lb from a 105 pec deck fly")
        let lighter = StrengthMilestones.bests([R(exercise: "Bench press", date: today, weight: 130, reps: 5)])
        XCTAssertEqual(StrengthMilestones.nextMilestone(for: lighter["Bench press"]!)?.label, "one plate (135) on bench press")
    }
}
