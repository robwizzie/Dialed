//
//  DailyScoreSnapshotterTests.swift
//  DialedTests
//
//  Verifies upsert behavior, force/skip logic, range fetches, and the
//  end-to-end backfill loop.
//

import XCTest
import SwiftData
@testable import Dialed

@MainActor
final class DailyScoreSnapshotterTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: DailyScoreSnapshot.self,
                SleepSession.self,
                BiometricSnapshot.self,
                PersonalBaseline.self,
                ContextEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - Snapshot writes

    func testSnapshot_writesARowForADayWithNoData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())

        let row = DailyScoreSnapshotter.snapshot(for: today, context: context)

        XCTAssertEqual(row.logicalDate, today)
        // No sleep → recovery nil; no mood/energy events → energy nil.
        XCTAssertNil(row.recoveryScore)
        XCTAssertNil(row.readinessScore)
        XCTAssertNil(row.energyScore)
        // Strain always computes (defaults to 0 when no load).
        XCTAssertNotNil(row.strainScore)
    }

    func testSnapshot_upsertsRatherThanInserts() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())

        _ = DailyScoreSnapshotter.snapshot(for: today, context: context)
        _ = DailyScoreSnapshotter.snapshot(for: today, context: context)
        _ = DailyScoreSnapshotter.snapshot(for: today, context: context)

        let all = try context.fetch(FetchDescriptor<DailyScoreSnapshot>())
        XCTAssertEqual(all.count, 1, "Same-day snapshot calls must upsert")
    }

    func testSnapshot_forceFalseSkipsRecentRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())

        let first = DailyScoreSnapshotter.snapshot(for: today, context: context)
        let firstStamp = first.computedAt

        // Immediate re-call with force:false → should return existing
        // without rewriting computedAt.
        let second = DailyScoreSnapshotter.snapshot(for: today, context: context, force: false)
        XCTAssertEqual(second.computedAt, firstStamp,
                       "force:false within the 60s window should preserve computedAt")
    }

    func testSnapshot_forceTrueAlwaysRewrites() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())

        let first = DailyScoreSnapshotter.snapshot(for: today, context: context)
        let firstStamp = first.computedAt

        // Sleep briefly enough that computedAt advances.
        Thread.sleep(forTimeInterval: 0.05)

        let second = DailyScoreSnapshotter.snapshot(for: today, context: context, force: true)
        XCTAssertGreaterThan(second.computedAt, firstStamp,
                             "force:true must always rewrite computedAt")
    }

    // MARK: - Range fetch

    func testFetchRange_returnsAscendingByDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Snapshot the last 5 days out of order.
        let offsets = [3, 0, 4, 1, 2]
        for offset in offsets {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            _ = DailyScoreSnapshotter.snapshot(for: day, context: context)
        }

        let from = cal.date(byAdding: .day, value: -4, to: today)!
        let rows = DailyScoreSnapshotter.fetch(from: from, to: today, context: context)
        XCTAssertEqual(rows.count, 5)
        for i in 1..<rows.count {
            XCTAssertLessThan(rows[i - 1].logicalDate, rows[i].logicalDate,
                              "Range fetch must be ascending")
        }
    }

    // MARK: - Backfill

    func testBackfill_writesOneSnapshotPerDayAndIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext

        DailyScoreSnapshotter.backfill(days: 7, context: context)
        let firstPass = try context.fetch(FetchDescriptor<DailyScoreSnapshot>())
        XCTAssertEqual(firstPass.count, 7)

        // Call again — must not create duplicates.
        DailyScoreSnapshotter.backfill(days: 7, context: context)
        let secondPass = try context.fetch(FetchDescriptor<DailyScoreSnapshot>())
        XCTAssertEqual(secondPass.count, 7, "Backfill must be idempotent")
    }

    func testBackfill_skipsDaysThatAlreadyHaveRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!

        // Pre-seed a snapshot for "3 days ago" with a recognizable
        // computedAt. Backfill should leave it alone.
        let preExisting = DailyScoreSnapshotter.snapshot(for: threeDaysAgo, context: context)
        let preStamp = preExisting.computedAt
        Thread.sleep(forTimeInterval: 0.05)

        DailyScoreSnapshotter.backfill(days: 7, context: context)

        let refetched = DailyScoreSnapshotter.fetch(logicalDate: threeDaysAgo, context: context)
        XCTAssertNotNil(refetched)
        XCTAssertEqual(refetched?.computedAt, preStamp,
                       "Backfill must skip days that already have a snapshot")
    }

    // MARK: - With real data

    func testSnapshot_recoveryIsPopulatedWhenSleepExists() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Insert a SleepSession for today.
        let sleep = SleepSession(
            startTime: cal.date(byAdding: .hour, value: -1, to: today)!,
            endTime: cal.date(byAdding: .hour, value: 7, to: today)!,
            inBedMinutes: 480,
            asleepMinutes: 450,
            source: .manual
        )
        context.insert(sleep)
        try context.save()

        let row = DailyScoreSnapshotter.snapshot(for: today, context: context)
        XCTAssertNotNil(row.recoveryScore,
                        "Recovery should be populated when a SleepSession exists for the day")
        XCTAssertNotNil(row.readinessScore,
                        "Readiness should populate as a function of Recovery")
        XCTAssertNotNil(row.recoveryConfidence)
    }
}
