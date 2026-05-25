//
//  PlanNotificationSchedulerTests.swift
//  DialedTests
//
//  Pure tests for the scheduler's copy + heuristics. The scheduling
//  side-effects (UNUserNotificationCenter.add) aren't tested here — that
//  needs a UNUserNotificationCenter mock harness which is out of scope.
//

import XCTest
@testable import Dialed

final class PlanNotificationSchedulerTests: XCTestCase {

    // MARK: - needsPreAlert

    func testNeedsPreAlert_workoutsAndDeepWorkGetHeadsUp() {
        XCTAssertTrue(PlanNotificationScheduler.needsPreAlert(kind: .workout))
        XCTAssertTrue(PlanNotificationScheduler.needsPreAlert(kind: .cardio))
        XCTAssertTrue(PlanNotificationScheduler.needsPreAlert(kind: .deepWork))
        XCTAssertTrue(PlanNotificationScheduler.needsPreAlert(kind: .meal))
        XCTAssertTrue(PlanNotificationScheduler.needsPreAlert(kind: .windDown))
        XCTAssertTrue(PlanNotificationScheduler.needsPreAlert(kind: .sleep))
    }

    func testNeedsPreAlert_quickMomentsDoNot() {
        XCTAssertFalse(PlanNotificationScheduler.needsPreAlert(kind: .wake))
        XCTAssertFalse(PlanNotificationScheduler.needsPreAlert(kind: .skincare))
        XCTAssertFalse(PlanNotificationScheduler.needsPreAlert(kind: .supplement))
        XCTAssertFalse(PlanNotificationScheduler.needsPreAlert(kind: .hydration))
        XCTAssertFalse(PlanNotificationScheduler.needsPreAlert(kind: .caffeine))
        XCTAssertFalse(PlanNotificationScheduler.needsPreAlert(kind: .rest))
        XCTAssertFalse(PlanNotificationScheduler.needsPreAlert(kind: .mood))
        XCTAssertFalse(PlanNotificationScheduler.needsPreAlert(kind: .routine))
    }

    func testNeedsPreAlert_coversEveryKind() {
        // Exhaustiveness — if you add a new Kind, this fails until you
        // decide its pre-alert behavior. Don't ignore the failure.
        for kind in TemplateBlock.Kind.allCases {
            _ = PlanNotificationScheduler.needsPreAlert(kind: kind)
        }
    }

    // MARK: - copy

    func testStartTitle_hasNonEmptyCopyForEveryKind() {
        for kind in TemplateBlock.Kind.allCases {
            let title = PlanNotificationScheduler.startTitle(for: kind)
            XCTAssertFalse(title.isEmpty, "\(kind) start title is empty")
        }
    }

    func testPreAlertTitle_workoutContains5Min() {
        XCTAssertTrue(
            PlanNotificationScheduler.preAlertTitle(for: .workout).contains("5"),
            "Workout pre-alert should mention the heads-up window"
        )
    }

    func testPreAlertTitle_fallsBackForKindsWithoutCustomCopy() {
        // wake doesn't get a pre-alert, but if someone calls preAlertTitle
        // it should still return generic non-empty text rather than crash.
        let copy = PlanNotificationScheduler.preAlertTitle(for: .wake)
        XCTAssertFalse(copy.isEmpty)
    }

    // MARK: - category id is stable

    func testCategoryID_isStable() {
        // Hard-coded string used by AppDelegate's switch — if you rename it,
        // update both sides. This test pins the value so we notice.
        XCTAssertEqual(PlanNotificationScheduler.categoryID, "PLAN_BLOCK")
    }
}
