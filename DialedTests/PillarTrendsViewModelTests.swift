//
//  PillarTrendsViewModelTests.swift
//  DialedTests
//
//  Covers the summary aggregation + trend slope calc. The fetch helpers
//  are exercised via an in-memory SwiftData container with synthetic
//  SleepSession + BiometricSnapshot rows.
//

import XCTest
import SwiftData
@testable import Dialed

@MainActor
final class PillarTrendsViewModelTests: XCTestCase {

    // MARK: - Window enum

    func testWindow_dayCounts() {
        XCTAssertEqual(PillarTrendsViewModel.Window.week.days, 7)
        XCTAssertEqual(PillarTrendsViewModel.Window.twoWeeks.days, 14)
        XCTAssertEqual(PillarTrendsViewModel.Window.month.days, 30)
    }

    // MARK: - Summary on a synthetic series

    func testSummary_computesAvgMinMaxOverScoredDaysOnly() async {
        let vm = PillarTrendsViewModel()
        // Inject a synthetic series via the published series dictionary.
        let today = Date()
        let cal = Calendar.current
        let points: [PillarTrendsViewModel.DailyPoint] = (0..<5).map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            // Mix some nils to make sure they're skipped.
            let score: Int? = offset == 2 ? nil : (40 + offset * 5)
            return .init(date: date, score: score)
        }
        vm.series = [.recovery: points]

        let summary = vm.summary(for: .recovery)
        // Scored values: 40, 45, (skip), 55, 60 → avg = 50, min = 40, max = 60.
        XCTAssertEqual(summary.average, 50)
        XCTAssertEqual(summary.min, 40)
        XCTAssertEqual(summary.max, 60)
    }

    func testSummary_returnsAllNilWhenNoData() {
        let vm = PillarTrendsViewModel()
        vm.series = [.recovery: []]
        let summary = vm.summary(for: .recovery)
        XCTAssertNil(summary.average)
        XCTAssertNil(summary.min)
        XCTAssertNil(summary.max)
        XCTAssertNil(summary.trendPerDay)
    }

    func testSummary_trendIsPositiveForRisingSeries() {
        let vm = PillarTrendsViewModel()
        let today = Date()
        let cal = Calendar.current
        // Strictly increasing daily scores: 50, 55, 60, 65, 70
        let rising: [PillarTrendsViewModel.DailyPoint] = (0..<5).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: today)!
            return .init(date: date, score: 50 + offset * 5)
        }
        vm.series = [.recovery: rising]
        let summary = vm.summary(for: .recovery)
        XCTAssertNotNil(summary.trendPerDay)
        XCTAssertGreaterThan(summary.trendPerDay!, 0)
        // Slope should be ~5 pts/day for this series.
        XCTAssertEqual(summary.trendPerDay!, 5.0, accuracy: 0.01)
    }

    func testSummary_trendIsNegativeForFallingSeries() {
        let vm = PillarTrendsViewModel()
        let today = Date()
        let cal = Calendar.current
        let falling: [PillarTrendsViewModel.DailyPoint] = (0..<5).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: today)!
            return .init(date: date, score: 80 - offset * 4)
        }
        vm.series = [.recovery: falling]
        let summary = vm.summary(for: .recovery)
        XCTAssertNotNil(summary.trendPerDay)
        XCTAssertLessThan(summary.trendPerDay!, 0)
        XCTAssertEqual(summary.trendPerDay!, -4.0, accuracy: 0.01)
    }

    func testSummary_trendIsNilWithSinglePoint() {
        let vm = PillarTrendsViewModel()
        vm.series = [.recovery: [.init(date: Date(), score: 60)]]
        XCTAssertNil(vm.summary(for: .recovery).trendPerDay)
    }

    // MARK: - load() against in-memory store

    func testLoad_emitsExactlyWindowDaysOfPoints() async throws {
        let container = try ModelContainer(
            for: SleepSession.self,
                BiometricSnapshot.self,
                PersonalBaseline.self,
                ContextEvent.self,
                DailyScoreSnapshot.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let vm = PillarTrendsViewModel()
        vm.window = .week
        vm.load(context: context)

        // Every pillar should have exactly 7 entries even when there's no
        // underlying data (scores will be nil for sleep-dependent pillars).
        for pillar in PillarTrendsViewModel.Pillar.allCases {
            XCTAssertEqual(vm.series[pillar]?.count, 7,
                           "\(pillar) should have one point per day in the window")
        }
    }

    func testLoad_emptySleepProducesNilRecoveryScore() async throws {
        let container = try ModelContainer(
            for: SleepSession.self,
                BiometricSnapshot.self,
                PersonalBaseline.self,
                ContextEvent.self,
                DailyScoreSnapshot.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let vm = PillarTrendsViewModel()
        vm.load(context: container.mainContext)
        let recoveryPoints = vm.series[.recovery] ?? []
        XCTAssertFalse(recoveryPoints.isEmpty)
        XCTAssertTrue(recoveryPoints.allSatisfy { $0.score == nil },
                      "Without any SleepSession data, every Recovery point should be nil")
    }
}
