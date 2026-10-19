//
//  WorkoutTextParserTests.swift
//  DialedTests
//
//  Typed gym notes become the right sets on the right plan exercises, and
//  training a later day's workout swaps the week around it.
//

import XCTest
@testable import Dialed

final class WorkoutTextParserTests: XCTestCase {

    private let known = ["Barbell back squat", "Bench press", "Cable fly", "Dumbbell shoulder press",
                         "Barbell Romanian deadlift", "Cable lat pulldown", "One-arm dumbbell row (bench)",
                         "Cable face pull", "Dumbbell goblet squat", "Push-up (feet on bench when easy)"]

    private func sets(_ e: WorkoutTextParser.ParsedExercise) -> [String] {
        e.sets.map { ($0.weight.map { "\(Int($0))" } ?? "bw") + "x\($0.reps)" }
    }

    func testCommonFormats() {
        let p = WorkoutTextParser.parse("bench 185x8x4, squat 225 5x5, lat pulldown 120 3x10", known: known)
        XCTAssertEqual(p.map(\.name), ["Bench press", "Barbell back squat", "Cable lat pulldown"])
        XCTAssertEqual(sets(p[0]), Array(repeating: "185x8", count: 4))
        XCTAssertEqual(sets(p[1]), Array(repeating: "225x5", count: 5))
        XCTAssertEqual(sets(p[2]), Array(repeating: "120x10", count: 3))
    }

    func testAtWeightRepListsAndBodyweight() {
        let p = WorkoutTextParser.parse("rdl 3x8 @ 155; bench 135x10, 155x8, 175x6\npushups 3x15", known: known)
        XCTAssertEqual(p[0].name, "Barbell Romanian deadlift")
        XCTAssertEqual(sets(p[0]), ["155x8", "155x8", "155x8"])
        XCTAssertEqual(sets(p[1]), ["135x10", "155x8", "175x6"])
        XCTAssertEqual(p[2].name, "Push-up (feet on bench when easy)")
        XCTAssertEqual(sets(p[2]), ["bwx15", "bwx15", "bwx15"])
        let reps = WorkoutTextParser.parse("shoulder press 45 for 10, 9, 8", known: known)
        XCTAssertEqual(sets(reps[0]), ["45x10", "45x9", "45x8"])
    }

    func testCardioAndUnknownNames() {
        let p = WorkoutTextParser.parse("goblet squats 70 3x12, incline db 60x10, walk 1.2 miles, bike 20 min", known: known)
        XCTAssertEqual(p[0].name, "Dumbbell goblet squat")
        XCTAssertEqual(p[1].name, "Incline dumbbell")
        XCTAssertEqual(p[2].miles, 1.2)
        XCTAssertEqual(p[3].minutes, 20)
    }

    func testTrainingBOnAnADaySwapsTheWeek() {
        let cal = Calendar.current
        let wed = cal.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        let fri = cal.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        let upcoming = [(date: wed, session: WorkoutProgram.strengthB), (date: fri, session: WorkoutProgram.strengthC(rounds: 3))]
        let didB = ["Barbell Romanian deadlift", "Cable lat pulldown", "Cable face pull"]
        XCTAssertEqual(WeekPlanAdjuster.swapTarget(logged: didB, todayPlan: WorkoutProgram.strengthA, upcoming: upcoming), wed)
        XCTAssertNil(WeekPlanAdjuster.swapTarget(logged: ["Bench press", "Barbell back squat"],
                                                 todayPlan: WorkoutProgram.strengthA, upcoming: upcoming))
    }
}
