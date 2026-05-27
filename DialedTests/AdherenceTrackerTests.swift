//
//  AdherenceTrackerTests.swift
//  DialedTests
//
//  Exercises summary(): scoreable filter, status counting, the
//  "ignored = past-but-still-upcoming" bucket, and the nil-when-empty
//  contract.
//

import XCTest
import SwiftData
@testable import Dialed

@MainActor
final class AdherenceTrackerTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: DailyPlan.self, PlanBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // Helper — insert a plan with N blocks at given times, return the plan.
    @discardableResult
    private func insertPlan(
        on day: Date,
        blocks: [(kind: TemplateBlock.Kind, startTime: Date, status: PlanBlock.Status)],
        context: ModelContext
    ) -> DailyPlan {
        let plan = DailyPlan(date: day)
        context.insert(plan)
        var planBlocks: [PlanBlock] = []
        for spec in blocks {
            let b = PlanBlock(
                kind: spec.kind,
                title: "\(spec.kind.rawValue)",
                startTime: spec.startTime
            )
            b.plan = plan
            switch spec.status {
            case .done:    b.markDone()
            case .skipped: b.markSkipped(reason: nil)
            case .upcoming, .active, .due:
                break  // default state
            }
            context.insert(b)
            planBlocks.append(b)
        }
        plan.blocks = planBlocks
        try? context.save()
        return plan
    }

    // MARK: - Empty store

    func testWeeklyAdherence_returnsNilWithNoPlans() throws {
        let container = try makeContainer()
        XCTAssertNil(AdherenceTracker.weeklyAdherence(context: container.mainContext))
    }

    // MARK: - All done

    func testWeeklyAdherence_allDoneReturns1() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let morning = cal.date(byAdding: .hour, value: 7, to: yesterday)!

        insertPlan(on: yesterday, blocks: [
            (.workout, morning, .done),
            (.meal, cal.date(byAdding: .hour, value: 1, to: morning)!, .done),
            (.skincare, cal.date(byAdding: .hour, value: 2, to: morning)!, .done)
        ], context: context)

        let adherence = AdherenceTracker.weeklyAdherence(context: context)
        XCTAssertEqual(adherence, 1.0)
    }

    // MARK: - Mixed

    func testWeeklyAdherence_mixedDoneAndSkippedAndIgnored() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let morning = cal.date(byAdding: .hour, value: 7, to: yesterday)!

        insertPlan(on: yesterday, blocks: [
            (.workout,    morning,                                           .done),
            (.meal,       cal.date(byAdding: .hour, value: 1, to: morning)!, .done),
            (.skincare,   cal.date(byAdding: .hour, value: 2, to: morning)!, .skipped),
            (.supplement, cal.date(byAdding: .hour, value: 3, to: morning)!, .upcoming),  // past + upcoming = ignored
            (.hydration,  cal.date(byAdding: .hour, value: 4, to: morning)!, .upcoming)   // past + upcoming = ignored
        ], context: context)

        let summary = AdherenceTracker.summary(context: context)
        XCTAssertEqual(summary.done, 2)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.ignored, 2)
        XCTAssertEqual(summary.pending, 0)
        XCTAssertEqual(summary.scored, 5)
        XCTAssertEqual(summary.adherence, 0.4)
    }

    // MARK: - Pending vs ignored

    func testSummary_futureUpcomingIsPendingNotIgnored() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // All blocks scheduled in the future (next 7 days). Should ALL
        // be pending — adherence is nil because nothing's been scored.
        var blocks: [(kind: TemplateBlock.Kind, startTime: Date, status: PlanBlock.Status)] = []
        for offset in 1...3 {
            let future = cal.date(byAdding: .day, value: offset, to: today)!
            blocks.append((.workout, cal.date(byAdding: .hour, value: 7, to: future)!, .upcoming))
        }
        // Insert as a plan dated today so the date-range filter catches it.
        insertPlan(on: today, blocks: blocks, context: context)

        let summary = AdherenceTracker.summary(context: context)
        XCTAssertEqual(summary.pending, 3)
        XCTAssertEqual(summary.ignored, 0)
        XCTAssertEqual(summary.done, 0)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertNil(summary.adherence)
    }

    // MARK: - Scoreable filter

    func testSummary_excludesStatusAnchorBlocks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let morning = cal.date(byAdding: .hour, value: 7, to: yesterday)!

        // wake/sleep/mood/rest should NOT count toward adherence at all,
        // even when marked done. Only the workout counts.
        insertPlan(on: yesterday, blocks: [
            (.wake,    morning, .done),
            (.sleep,   cal.date(byAdding: .hour, value: 14, to: morning)!, .done),
            (.mood,    cal.date(byAdding: .hour, value: 4,  to: morning)!, .skipped),
            (.rest,    cal.date(byAdding: .hour, value: 3,  to: morning)!, .done),
            (.workout, cal.date(byAdding: .hour, value: 1,  to: morning)!, .done)
        ], context: context)

        let summary = AdherenceTracker.summary(context: context)
        XCTAssertEqual(summary.done, 1, "Only the workout should count")
        XCTAssertEqual(summary.scored, 1)
        XCTAssertEqual(summary.adherence, 1.0)
    }

    // MARK: - Window boundary

    func testSummary_excludesBlocksOutsideTheWindow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // 10 days ago — outside the 7-day window.
        let oldDay = cal.date(byAdding: .day, value: -10, to: today)!
        let morning = cal.date(byAdding: .hour, value: 7, to: oldDay)!

        insertPlan(on: oldDay, blocks: [
            (.workout, morning, .skipped),
            (.workout, cal.date(byAdding: .hour, value: 1, to: morning)!, .skipped)
        ], context: context)

        XCTAssertNil(AdherenceTracker.weeklyAdherence(context: context),
                     "Skipped blocks from 10 days ago should not appear in a 7-day window")
    }
}
