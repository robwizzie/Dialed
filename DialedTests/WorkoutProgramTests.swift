//
//  WorkoutProgramTests.swift
//  DialedTests
//
//  The weekly template lands on the right days, phases count back from
//  the goal day, and event week tapers.
//

import XCTest
@testable import Dialed

final class WorkoutProgramTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private func date(_ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d))!
    }
    private lazy var start = date(10, 19)   // Monday
    private lazy var goal = date(11, 19)    // Thursday

    private func session(_ m: Int, _ d: Int) -> WorkoutProgram.Session {
        WorkoutProgram.session(on: date(m, d), start: start, goal: goal, calendar: calendar)
    }

    func testWeeklyTemplate() {
        XCTAssertEqual(session(10, 19).title, WorkoutProgram.strengthA.title)  // Mon
        XCTAssertEqual(session(10, 20).kind, .bike)                            // Tue
        XCTAssertEqual(session(10, 21).title, WorkoutProgram.strengthB.title)  // Wed
        XCTAssertEqual(session(10, 22).kind, .walk)                            // Thu
        XCTAssertEqual(session(10, 23).notes.first?.hasPrefix("3 rounds"), true) // Fri, base week
        XCTAssertEqual(session(10, 24).walk, "45-min long walk with Peaches")  // Sat
        XCTAssertEqual(session(10, 25).kind, .rest)                            // Sun
        XCTAssertEqual(session(10, 30).notes.first?.hasPrefix("4 rounds"), true) // Fri, build
    }

    func testPhasesCountBackFromGoal() {
        func phase(_ m: Int, _ d: Int) -> WorkoutProgram.Phase {
            WorkoutProgram.phase(on: date(m, d), start: start, goal: goal, calendar: calendar)
        }
        XCTAssertEqual(phase(10, 20), .base)
        XCTAssertEqual(phase(10, 27), .build)
        XCTAssertEqual(phase(11, 9), .peak)
        XCTAssertEqual(phase(11, 16), .eventWeek)
        XCTAssertEqual(phase(11, 20), .after)
    }

    func testPeakAddsBikeAndEventWeekTapers() {
        let peakMonday = session(11, 9)   // Mon Nov 9
        XCTAssertEqual(peakMonday.minutes, 60)
        XCTAssertEqual(peakMonday.exercises.last?.name, "Bike, steady")
        XCTAssertEqual(session(11, 16).title, "Strength C · Full-body circuit")
        XCTAssertEqual(session(11, 17).kind, .light)
        XCTAssertEqual(session(11, 18).kind, .light)
        XCTAssertEqual(session(11, 19).kind, .event)
    }
}
