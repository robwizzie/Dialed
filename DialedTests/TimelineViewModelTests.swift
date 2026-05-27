//
//  TimelineViewModelTests.swift
//  DialedTests
//
//  Covers the pure parts of TimelineViewModel: dayStrip windowing,
//  selection normalization, grouping into hour buckets.
//

import XCTest
import SwiftData
@testable import Dialed

@MainActor
final class TimelineViewModelTests: XCTestCase {

    // MARK: - dayStrip

    func testDayStrip_returnsNineDaysIncludingToday() async {
        let vm = TimelineViewModel()
        XCTAssertEqual(vm.dayStrip.count, 9, "Expected -7 through +1 = 9 cells")
    }

    func testDayStrip_isAscendingInTime() async {
        let vm = TimelineViewModel()
        let dates = vm.dayStrip
        for i in 1..<dates.count {
            XCTAssertLessThan(dates[i - 1], dates[i])
        }
    }

    func testDayStrip_containsToday() async {
        let vm = TimelineViewModel()
        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertTrue(vm.dayStrip.contains(today))
    }

    // MARK: - select normalization

    func testSelect_normalizesToStartOfDay() async {
        let vm = TimelineViewModel()
        // 11:42 AM on some day
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 25
        components.hour = 11
        components.minute = 42
        let messy = Calendar.current.date(from: components)!
        vm.select(messy)
        let expected = Calendar.current.startOfDay(for: messy)
        XCTAssertEqual(vm.selectedDate, expected)
    }

    // MARK: - groupedByHour

    func testGroupedByHour_bucketsByClockHour() async throws {
        let container = try ModelContainer(
            for: ContextEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let calendar = Calendar.current
        var dc = DateComponents()
        dc.year = 2026; dc.month = 5; dc.day = 25

        dc.hour = 7;  dc.minute = 12
        let earlyMorning = calendar.date(from: dc)!
        dc.hour = 7;  dc.minute = 45
        let lateMorning = calendar.date(from: dc)!
        dc.hour = 12; dc.minute = 30
        let noon = calendar.date(from: dc)!
        dc.hour = 20; dc.minute = 5
        let evening = calendar.date(from: dc)!

        let events = [
            ContextEvent.water(8, at: earlyMorning),
            ContextEvent.caffeine(milligrams: 95, at: lateMorning),
            ContextEvent.meal(calories: 600, protein: 35, at: noon),
            ContextEvent.mood(4, at: evening)
        ]
        for e in events { context.insert(e) }
        try context.save()

        let vm = TimelineViewModel()
        vm.select(noon)
        vm.refresh(context: context)

        let grouped = vm.groupedByHour
        XCTAssertEqual(grouped.count, 3, "Expected three distinct hours: 7, 12, 20")
        XCTAssertEqual(grouped[0].hour, 7)
        XCTAssertEqual(grouped[0].events.count, 2)
        XCTAssertEqual(grouped[1].hour, 12)
        XCTAssertEqual(grouped[2].hour, 20)
    }

    func testGroupedByHour_sortsEventsWithinBucketAscending() async throws {
        let container = try ModelContainer(
            for: ContextEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let calendar = Calendar.current
        var dc = DateComponents()
        dc.year = 2026; dc.month = 5; dc.day = 25; dc.hour = 9

        dc.minute = 45
        let later = calendar.date(from: dc)!
        dc.minute = 10
        let earlier = calendar.date(from: dc)!

        // Insert later one first so we know ordering is driven by sort, not insertion.
        context.insert(ContextEvent.water(16, at: later))
        context.insert(ContextEvent.caffeine(milligrams: 60, at: earlier))
        try context.save()

        let vm = TimelineViewModel()
        vm.select(earlier)
        vm.refresh(context: context)

        let grouped = vm.groupedByHour
        XCTAssertEqual(grouped.count, 1)
        let bucket = grouped[0]
        XCTAssertEqual(bucket.events.first?.timestamp, earlier)
        XCTAssertEqual(bucket.events.last?.timestamp, later)
    }

    func testRefresh_onlyFetchesSelectedLogicalDate() async throws {
        let container = try ModelContainer(
            for: ContextEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(12 * 3600)

        context.insert(ContextEvent.water(10, at: today.addingTimeInterval(10 * 3600)))
        context.insert(ContextEvent.water(20, at: yesterday))
        try context.save()

        let vm = TimelineViewModel()
        vm.select(today)
        vm.refresh(context: context)

        XCTAssertEqual(vm.eventCount, 1, "Only today's event should appear")
        XCTAssertEqual(vm.orderedEvents.first?.value, 10)
    }
}
