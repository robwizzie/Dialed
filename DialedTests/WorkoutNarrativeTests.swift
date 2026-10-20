//
//  WorkoutNarrativeTests.swift
//  DialedTests
//
//  A workout texted like a sentence lands as the right exercises, sets,
//  session time and cardio.
//

import XCTest
@testable import Dialed

final class WorkoutNarrativeTests: XCTestCase {

    private let known = ["Bench press", "Cable fly", "Cable lat pulldown", "Barbell back squat",
                         "One-arm dumbbell row (bench)", "Dumbbell reverse lunge", "Dumbbell walking lunge"]

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func sets(_ e: WorkoutTextParser.ParsedExercise) -> [String] {
        e.sets.map { ($0.weight.map { "\(Int($0))" } ?? "bw") + "x\($0.reps)" }
    }

    private func clock(_ d: Date?) -> String {
        guard let d else { return "-" }
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour!, c.minute!)
    }

    func testChestDayAsTexted() {
        let text = """
        Today I did flat bench press, 1 set of 10 for 135lbs, 1 set of 10 for 145lbs, and 1 set of 8 for 155lbs. \
        Then we did 3 sets of the chest workout where you pull the two sides together to workout inner chest and we \
        did 3 sets of 10 of 100lbs and then we finished with incline bench, 1 set of 10 with 90lbs, 1 set of 10 with \
        110lbs and one set of 6 with 140lbs and that was the workout today. We worked out from 6:15-6:45 \
        (I ran a mile on 5 speed from 6-6:15)
        """
        let now = ISO8601DateFormatter().date(from: "2026-10-20T23:30:00Z")!   // 7:30 PM in New York
        let r = WorkoutNarrative.read(text, known: known, now: now, calendar: calendar)

        XCTAssertEqual(r.exercises.map(\.name), ["Bench press", "Pec deck fly", "Incline bench press"])
        XCTAssertEqual(sets(r.exercises[0]), ["135x10", "145x10", "155x8"])
        XCTAssertEqual(sets(r.exercises[1]), ["100x10", "100x10", "100x10"])
        XCTAssertEqual(sets(r.exercises[2]), ["90x10", "110x10", "140x6"])

        XCTAssertEqual(clock(r.start), "18:15")
        XCTAssertEqual(clock(r.end), "18:45")
        XCTAssertEqual(r.minutes, 30)

        XCTAssertEqual(r.cardio.count, 1)
        XCTAssertEqual(r.cardio[0].kind, "Run")
        XCTAssertEqual(r.cardio[0].miles, 1)
        XCTAssertEqual(r.cardio[0].minutes, 15)
        XCTAssertEqual(r.cardio[0].speedMph, 5)
        XCTAssertEqual(clock(r.cardio[0].start), "18:00")
    }

    func testMixedSentencesAndDistinctNames() {
        let r = WorkoutNarrative.read("squats 3 sets of 5 at 225, then lat pulldown 3x10 @ 120 and reverse lunges 3 sets of 10 with 40lbs. leg press 4 sets of 12 at 270. walked 2 miles in 30 min",
                                      known: known)
        XCTAssertEqual(r.exercises.map(\.name), ["Barbell back squat", "Cable lat pulldown", "Dumbbell reverse lunge", "Leg press"])
        XCTAssertEqual(sets(r.exercises[0]), ["225x5", "225x5", "225x5"])
        XCTAssertEqual(r.cardio.first?.kind, "Walk")
        XCTAssertEqual(r.cardio.first?.miles, 2)
    }

    func testTreadmillSpeedGivesDistance() {
        let r = WorkoutNarrative.read("ran 20 minutes on the treadmill at 6.5 speed")
        XCTAssertEqual(r.cardio.first?.speedMph, 6.5)
        XCTAssertEqual(r.cardio.first?.miles ?? 0, 2.17, accuracy: 0.01)
    }

    func testMorningTimesStayInTheMorning() {
        let now = ISO8601DateFormatter().date(from: "2026-10-20T13:00:00Z")!   // 9 AM in New York
        let r = WorkoutNarrative.read("bench 135x10 from 7-8", now: now, calendar: calendar)
        XCTAssertEqual(clock(r.start), "7:00")
        XCTAssertEqual(clock(r.end), "8:00")
    }

    func testInclineIsNotFlatBench() {
        XCTAssertEqual(WorkoutTextParser.canonical("incline bench", known: known), "Incline bench press")
        XCTAssertEqual(WorkoutTextParser.canonical("leg press", known: known), "Leg press")
        XCTAssertEqual(WorkoutTextParser.canonical("flat bench", known: known), "Bench press")
    }
}

final class WorkoutDetectorTests: XCTestCase {

    private func w(_ id: String, _ kind: DetectedWorkout.Kind, _ start: Double, _ end: Double, miles: Double? = nil) -> DetectedWorkout {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return DetectedWorkout(id: id, title: id, kind: kind, start: base.addingTimeInterval(start * 60),
                               end: base.addingTimeInterval(end * 60), miles: miles, calories: nil, source: id)
    }

    func testSameSessionFromTwoSourcesCountsOnce() {
        let apple = [w("watch", .strength, 15, 45)]
        let google = [w("pixel", .strength, 16, 44), w("pixel-run", .run, 0, 15, miles: 1)]
        let merged = WorkoutDetector.merge(apple, google)
        XCTAssertEqual(merged.map(\.id), ["pixel-run", "watch"])
    }

    func testBlipsAreIgnoredAndGoogleTypesMap() {
        XCTAssertTrue(WorkoutDetector.merge([w("blip", .other, 0, 1)]).isEmpty)
        XCTAssertEqual(WorkoutDetector.kind(google: "WEIGHTLIFTING"), .strength)
        XCTAssertEqual(WorkoutDetector.kind(google: "TREADMILL_RUNNING"), .run)
        XCTAssertEqual(WorkoutDetector.kind(google: "WALKING"), .walk)
    }
}
