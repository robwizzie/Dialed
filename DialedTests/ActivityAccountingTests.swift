//
//  ActivityAccountingTests.swift
//  DialedTests
//
//  Walking Health already logged (any app, e.g. Mile A Day) isn't asked
//  about again, and nothing's calories count twice.
//

import XCTest
@testable import Dialed

final class ActivityAccountingTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minute: Double) -> Date { base.addingTimeInterval(minute * 60) }

    /// One sample per minute from `from` to `to`.
    private func perMinute(_ from: Int, _ to: Int, _ value: Double) -> [ActivityAccounting.Sample] {
        (from..<to).map { .init(start: at(Double($0)), end: at(Double($0 + 1)), value: value) }
    }

    func testAWalkHealthAlreadyHasIsNotAsked() {
        // 30 min at ~110 steps and 0.05 mi a minute.
        let v = ActivityAccounting.classify(start: at(0), end: at(30),
                                            steps: perMinute(0, 30, 110), distance: perMinute(0, 30, 0.05))
        guard case .alreadyCounted(let miles) = v else { return XCTFail("\(v)") }
        XCTAssertEqual(miles, 1.5, accuracy: 0.01)
    }

    func testAGameWithAWalkInItIsMixed() {
        // 10 of 40 minutes walking, the rest on a court.
        let v = ActivityAccounting.classify(start: at(0), end: at(40),
                                            steps: perMinute(0, 10, 100) + perMinute(10, 40, 30), distance: [])
        XCTAssertEqual(v, .mixed(walkingShare: 0.25))
    }

    func testNoStepsIsUnexplained() {
        XCTAssertEqual(ActivityAccounting.classify(start: at(0), end: at(45), steps: perMinute(0, 45, 8), distance: []),
                       .unexplained)
    }

    func testOneBigStepSampleIsSpreadOut() {
        // iPhone often logs one sample for a long walk: 3,000 steps over 30 min.
        let v = ActivityAccounting.classify(start: at(5), end: at(25),
                                            steps: [.init(start: at(0), end: at(30), value: 3_000)], distance: [])
        guard case .alreadyCounted = v else { return XCTFail("\(v)") }
    }

    func testWorkoutsArePaddedAndOverlapsCountOnce() {
        let busy = ActivityAccounting.busyIntervals([DateInterval(start: at(10), end: at(40))])
        XCTAssertEqual(busy[0].start, at(5))
        XCTAssertEqual(busy[0].end, at(45))
        // Two overlapping workouts cover 30 of 60 minutes, not 40.
        let share = ActivityAccounting.coveredShare(of: DateInterval(start: at(0), end: at(60)),
                                                    by: [DateInterval(start: at(0), end: at(20)), DateInterval(start: at(10), end: at(30))])
        XCTAssertEqual(share, 0.5, accuracy: 0.001)
    }

    func testEarnedCaloriesCountAWalkOnce() {
        func e(_ id: String, _ s: Double, _ en: Double, _ c: Double, _ src: EarnedCalories.Entry.Source) -> EarnedCalories.Entry {
            .init(id: id, name: id, symbol: "", start: at(s), end: at(en), calories: c, source: src)
        }
        // A Mile A Day walk inside a named hour of yard work: the yard work
        // keeps only its non-walk share.
        let day = EarnedCalories.combine([e("mile-a-day walk", 10, 30, 100, .watch), e("yard work", 0, 60, 300, .fun)])
        XCTAssertEqual(day.entries.map(\.id), ["yard work", "mile-a-day walk"])
        XCTAssertEqual(day.earned, 300)   // 100 + 300 × (1 − 20/60)
        // A logged walk the Mile A Day workout fully covers counts once.
        let once = EarnedCalories.combine([e("mile-a-day walk", 0, 20, 100, .watch), e("logged walk", 2, 18, 90, .logged)])
        XCTAssertEqual(once.earned, 100)
    }
}
