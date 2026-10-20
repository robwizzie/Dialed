//
//  StrengthProgressionTests.swift
//  DialedTests
//
//  Prescriptions parse, suggestions follow the progression rules, Epley
//  e1RM and the strength-vs-weight headline read right.
//

import XCTest
@testable import Dialed

final class StrengthProgressionTests: XCTestCase {

    typealias SP = StrengthProgression
    private func sets(_ weight: Double, _ reps: [Int]) -> [SP.LoggedSet] {
        reps.map { SP.LoggedSet(weight: weight, reps: $0) }
    }

    // MARK: Parsing

    func testParsesPlanPrescriptions() {
        XCTAssertEqual(SP.parse("4 × 8"), .setsReps(sets: 4, reps: 8, perSide: false))
        XCTAssertEqual(SP.parse("3 × 10 / leg"), .setsReps(sets: 3, reps: 10, perSide: true))
        XCTAssertEqual(SP.parse("3 × 12 each"), .setsReps(sets: 3, reps: 12, perSide: true))
        XCTAssertEqual(SP.parse("3 × 12 / side"), .setsReps(sets: 3, reps: 12, perSide: true))
        XCTAssertEqual(SP.parse("3 x 15"), .setsReps(sets: 3, reps: 15, perSide: false))
        XCTAssertEqual(SP.parse("45 s"), .duration(seconds: 45))
        XCTAssertEqual(SP.parse("15 min"), .duration(seconds: 900))
    }

    func testRejectsNonSetPrescriptions() {
        XCTAssertNil(SP.parse("× 6–8"))
        XCTAssertNil(SP.parse("45–60 min"))
        XCTAssertNil(SP.parse("8 rounds · 30 s hard / 90 s easy"))
        XCTAssertNil(SP.parse(""))
    }

    func testEveryPlanStrengthPrescriptionParses() {
        for e in WorkoutProgram.strengthA.exercises + WorkoutProgram.strengthB.exercises
            + WorkoutProgram.strengthC(rounds: 3).exercises + WorkoutProgram.light.exercises {
            XCTAssertNotNil(SP.parse(e.prescription), e.prescription)
        }
    }

    // MARK: Equipment

    func testEquipment() {
        XCTAssertEqual(SP.equipment(for: "Barbell back squat"), .barbellLower)
        XCTAssertEqual(SP.equipment(for: "Barbell Romanian deadlift"), .barbellLower)
        XCTAssertEqual(SP.equipment(for: "Bench press"), .barbell)
        XCTAssertEqual(SP.equipment(for: "Cable lat pulldown"), .cable)
        XCTAssertEqual(SP.equipment(for: "Cable woodchop + 1-min plank"), .cable)
        XCTAssertEqual(SP.equipment(for: "One-arm dumbbell row (bench)"), .dumbbell)
        XCTAssertEqual(SP.equipment(for: "Push-up (feet on bench when easy)"), .bodyweight)
    }

    // MARK: Suggestions

    func testFirstTimeHasNoSuggestion() {
        XCTAssertNil(SP.suggest(exerciseName: "Bench press", prescription: SP.parse("4 × 8"), lastSession: []))
        XCTAssertFalse(SP.firstTimeHint.isEmpty)
    }

    func testAllSetsHitAddsFiveForUpperBody() {
        let s = SP.suggest(exerciseName: "Bench press", prescription: SP.parse("4 × 8"), lastSession: sets(135, [8, 8, 8, 9]))
        XCTAssertEqual(s, SP.Suggestion(weight: 140, kind: .increase))
    }

    func testAllSetsHitAddsTenForSquatAndRDL() {
        XCTAssertEqual(SP.suggest(exerciseName: "Barbell back squat", prescription: SP.parse("4 × 8"),
                                  lastSession: sets(185, [8, 8, 8, 8]))?.weight, 195)
        XCTAssertEqual(SP.suggest(exerciseName: "Barbell Romanian deadlift", prescription: SP.parse("4 × 8"),
                                  lastSession: sets(155, [8, 8, 8, 8]))?.weight, 165)
    }

    func testCableAndDumbbellAddFive() {
        XCTAssertEqual(SP.suggest(exerciseName: "Cable lat pulldown", prescription: SP.parse("4 × 10"),
                                  lastSession: sets(100, [10, 10, 10, 10]))?.weight, 105)
        XCTAssertEqual(SP.suggest(exerciseName: "Dumbbell shoulder press", prescription: SP.parse("3 × 10"),
                                  lastSession: sets(35, [10, 10, 10]))?.weight, 40)
    }

    func testMissedTwoSetsRepeatsWeight() {
        let s = SP.suggest(exerciseName: "Bench press", prescription: SP.parse("4 × 8"), lastSession: sets(135, [8, 8, 7, 6]))
        XCTAssertEqual(s, SP.Suggestion(weight: 135, kind: .repeatWeight))
    }

    func testFewerSetsThanPrescribedDoesNotProgress() {
        let s = SP.suggest(exerciseName: "Bench press", prescription: SP.parse("4 × 8"), lastSession: sets(135, [8, 8, 8]))
        XCTAssertEqual(s?.kind, .repeatWeight)
    }

    func testFailedBadlyBacksOffFivePercent() {
        let s = SP.suggest(exerciseName: "Barbell back squat", prescription: SP.parse("4 × 8"), lastSession: sets(200, [6, 4, 3, 3]))
        XCTAssertEqual(s, SP.Suggestion(weight: 190, kind: .deload))
        // Light weights still drop at least one step.
        let light = SP.suggest(exerciseName: "Cable face pull", prescription: SP.parse("3 × 15"), lastSession: sets(30, [8, 6, 5]))
        XCTAssertEqual(light?.weight, 25)
    }

    func testUsesTopWeightAndIgnoresIncompleteSets() {
        var last = sets(95, [8])                         // lighter warm-up set
        last += sets(135, [8, 8, 8, 8])
        last.append(SP.LoggedSet(weight: 145, reps: 2, completed: false))
        XCTAssertEqual(SP.suggest(exerciseName: "Bench press", prescription: SP.parse("4 × 8"), lastSession: last)?.weight, 140)
    }

    func testNoSuggestionForTimedOrBodyweight() {
        XCTAssertNil(SP.suggest(exerciseName: "Dumbbell thruster", prescription: SP.parse("45 s"), lastSession: sets(25, [12])))
        XCTAssertNil(SP.suggest(exerciseName: "Push-up", prescription: SP.parse("2 × 10"), lastSession: sets(0, [10, 10])))
    }

    func testRounding() {
        XCTAssertEqual(SP.round(137.5 * 0.95), 130)
        XCTAssertEqual(SP.round(142), 140)
        XCTAssertEqual(SP.round(143), 145)
    }

    // MARK: e1RM

    func testEpley() {
        XCTAssertEqual(SP.epley(weight: 135, reps: 1), 135)
        XCTAssertEqual(SP.epley(weight: 150, reps: 10), 200, accuracy: 0.001)
        XCTAssertEqual(SP.epley(weight: 0, reps: 10), 0)
        XCTAssertEqual(SP.epley(weight: 100, reps: 0), 0)
    }

    func testSeriesSkipsEmptySessionsAndSortsByDate() {
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let d2 = d1.addingTimeInterval(86_400 * 7)
        let d3 = d1.addingTimeInterval(86_400 * 3)
        let series = SP.e1RMSeries([
            (date: d2, sets: sets(150, [10])),
            (date: d1, sets: sets(135, [8, 8])),
            (date: d3, sets: [SP.LoggedSet(weight: 145, reps: 8, completed: false)])
        ])
        XCTAssertEqual(series.map(\.date), [d1, d2])
        XCTAssertEqual(series.last?.e1RM ?? 0, 200, accuracy: 0.001)
    }

    func testMainLiftMatching() {
        XCTAssertTrue(SP.MainLift.squat.matches("Barbell back squat"))
        XCTAssertFalse(SP.MainLift.squat.matches("Dumbbell goblet squat"))
        XCTAssertTrue(SP.MainLift.bench.matches("Bench press"))
        XCTAssertFalse(SP.MainLift.bench.matches("One-arm dumbbell row (bench)"))
        XCTAssertTrue(SP.MainLift.row.matches("One-arm dumbbell row (bench)"))
        XCTAssertTrue(SP.MainLift.rdl.matches("Barbell Romanian deadlift"))
        XCTAssertFalse(SP.MainLift.rdl.matches("Dumbbell RDL"))
        XCTAssertTrue(SP.MainLift.latPulldown.matches("Cable lat pulldown"))
        XCTAssertTrue(SP.MainLift.shoulderPress.matches("Dumbbell shoulder press"))
    }

    func testHeadline() {
        XCTAssertEqual(SP.headline(lift: "Bench", e1RMChange: 10.2, weightChange: -6.4),
                       "Bench e1RM +10 lb while you're −6 lb")
        XCTAssertEqual(SP.headline(lift: "Squat", e1RMChange: 0, weightChange: nil), "Squat e1RM ±0 lb")
    }
}
