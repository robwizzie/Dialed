//
//  WidgetBridgeTests.swift
//  DialedTests
//
//  The app ↔ widget handshake: the snapshot survives the round trip, the
//  tap queue drains once (never logging a tap twice), widget totals add
//  queued taps on top, and a stale snapshot resets at the 4 AM day line.
//

import XCTest
@testable import Dialed

final class WidgetBridgeTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var bridge: WidgetBridge!

    override func setUp() {
        super.setUp()
        suiteName = "WidgetBridgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        bridge = WidgetBridge(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let shake = WidgetFavorite(id: UUID(), name: "Clear Whey Shake", calories: 90, protein: 20)

    private func snapshot(at updated: Date) -> WidgetSnapshot {
        WidgetSnapshot(waterOz: 40, waterTargetOz: 120, protein: 100, proteinTarget: 190,
                       calories: 1_000, calorieTarget: 2_200, favorites: [shake], updatedAt: updated)
    }

    // MARK: - Snapshot

    func testSnapshotRoundTrips() {
        XCTAssertNil(bridge.readSnapshot())
        let s = snapshot(at: Date(timeIntervalSince1970: 1_790_000_000))
        bridge.writeSnapshot(s)
        XCTAssertEqual(bridge.readSnapshot(), s)
    }

    func testDerivedValues() {
        var s = snapshot(at: Date())
        XCTAssertEqual(s.waterProgress, 40.0 / 120.0, accuracy: 0.0001)
        XCTAssertEqual(s.proteinLeft, 90)
        XCTAssertEqual(s.caloriesLeft, 1_200)
        s.waterOz = 200
        s.protein = 250
        XCTAssertEqual(s.waterProgress, 1)
        XCTAssertEqual(s.proteinLeft, 0)
    }

    func testMissingAppGroupIsANoOp() {
        let off = WidgetBridge(defaults: nil)
        XCTAssertFalse(off.isAvailable)
        off.enqueue(.water(16))
        off.writeSnapshot(snapshot(at: Date()))
        XCTAssertNil(off.readSnapshot())
        XCTAssertTrue(off.pending().isEmpty)
        XCTAssertTrue(off.drain().isEmpty)
    }

    // MARK: - Queue

    func testDrainReturnsOldestFirstAndEmptiesQueue() {
        let later = PendingLog.water(16, at: date(19, 12))
        let earlier = PendingLog.favorite(shake.id, at: date(19, 9))
        bridge.enqueue(later)
        bridge.enqueue(earlier)
        XCTAssertEqual(bridge.pending().count, 2)

        XCTAssertEqual(bridge.drain(), [earlier, later])
        XCTAssertTrue(bridge.pending().isEmpty)
        XCTAssertTrue(bridge.drain().isEmpty)
    }

    func testEnqueueIgnoresDuplicateIDs() {
        let log = PendingLog.water(16)
        bridge.enqueue(log)
        bridge.enqueue(log)
        XCTAssertEqual(bridge.pending(), [log])
    }

    func testRedeliveredLogIsNotDrainedTwice() {
        let log = PendingLog.water(16)
        bridge.enqueue(log)
        XCTAssertEqual(bridge.drain(), [log])

        // The same tap shows up again (e.g. a write that raced the drain).
        bridge.enqueue(log)
        XCTAssertTrue(bridge.drain().isEmpty)
        XCTAssertTrue(bridge.pending().isEmpty)

        // A new tap still goes through.
        let next = PendingLog.water(8)
        bridge.enqueue(next)
        XCTAssertEqual(bridge.drain(), [next])
    }

    func testProcessedMemoryIsBounded() {
        for _ in 0..<(WidgetBridge.processedMemory + 25) {
            bridge.enqueue(.water(1))
            _ = bridge.drain()
        }
        let remembered = defaults.stringArray(forKey: WidgetBridge.processedKey) ?? []
        XCTAssertEqual(remembered.count, WidgetBridge.processedMemory)
    }

    // MARK: - Optimistic totals

    func testDisplayAddsPendingTapsForToday() {
        let s = snapshot(at: date(19, 8))
        let pending = [
            PendingLog.water(16, at: date(19, 9)),
            PendingLog.water(16, at: date(19, 10)),
            PendingLog.favorite(shake.id, at: date(19, 11)),
            PendingLog.favorite(UUID(), at: date(19, 11)),   // unknown favorite: ignored
            PendingLog.water(16, at: date(18, 20))            // yesterday: ignored
        ]
        let shown = s.display(with: pending, now: date(19, 12), calendar: calendar)
        XCTAssertEqual(shown.waterOz, 72)
        XCTAssertEqual(shown.calories, 1_090)
        XCTAssertEqual(shown.protein, 120)
        XCTAssertEqual(shown.waterTargetOz, 120)
    }

    func testStaleSnapshotResetsAfterDayCutoff() {
        let s = snapshot(at: date(18, 22))
        // 2 AM still belongs to the 18th.
        XCTAssertEqual(s.display(with: [], now: date(19, 2), calendar: calendar).waterOz, 40)
        // 5 AM is a new day: start from zero, keep targets and favorites.
        let fresh = s.display(with: [.water(16, at: date(19, 5))], now: date(19, 5, 30), calendar: calendar)
        XCTAssertEqual(fresh.waterOz, 16)
        XCTAssertEqual(fresh.calories, 0)
        XCTAssertEqual(fresh.protein, 0)
        XCTAssertEqual(fresh.calorieTarget, 2_200)
        XCTAssertEqual(fresh.favorites, [shake])
    }

    func testLogicalDayUsesFourAMCutoff() {
        XCTAssertEqual(WidgetBridge.logicalDay(for: date(19, 3, 59), calendar: calendar),
                       calendar.startOfDay(for: date(18, 12)))
        XCTAssertEqual(WidgetBridge.logicalDay(for: date(19, 4), calendar: calendar),
                       calendar.startOfDay(for: date(19, 12)))
    }
}
