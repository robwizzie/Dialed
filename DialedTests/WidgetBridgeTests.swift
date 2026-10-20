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

    // MARK: - Meals

    func testPendingFavoritesJoinTodaysPlate() {
        var s = snapshot(at: date(19, 8))
        s.meals = [WidgetMeal(name: "Egg Wrap", calories: 380, protein: 30, time: date(19, 7))]
        let shown = s.display(with: [.favorite(shake.id, at: date(19, 11))], now: date(19, 12), calendar: calendar)
        XCTAssertEqual(shown.meals?.map(\.name), ["Egg Wrap", "Clear Whey Shake"])
        XCTAssertEqual(shown.meals?.last?.time, date(19, 11))
    }

    func testStaleSnapshotClearsMeals() {
        var s = snapshot(at: date(18, 20))
        s.meals = [WidgetMeal(name: "Egg Wrap", calories: 380, protein: 30, time: date(18, 19))]
        XCTAssertEqual(s.display(with: [], now: date(19, 9), calendar: calendar).meals, [])
    }

    func testVersionOneSnapshotStillDecodes() throws {
        // Written before meals existed.
        let json = """
        {"waterOz":40,"waterTargetOz":120,"protein":100,"proteinTarget":190,
         "calories":1000,"calorieTarget":2200,"favorites":[],"updatedAt":0}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.meals)
        XCTAssertEqual(decoded.waterOz, 40)
    }

    // MARK: - Insights

    private func insights(at updated: Date) -> WidgetInsights {
        var i = WidgetInsights.placeholder
        i.updatedAt = updated
        return i
    }

    func testInsightsRoundTrip() {
        XCTAssertNil(bridge.readInsights())
        let i = insights(at: Date(timeIntervalSince1970: 1_790_000_000))
        bridge.writeInsights(i)
        XCTAssertEqual(bridge.readInsights(), i)
    }

    func testInsightsDerivedValues() {
        let i = WidgetInsights.placeholder
        XCTAssertEqual(i.stepProgress, 0.742, accuracy: 0.0001)
        XCTAssertEqual(i.weightChange ?? 0, 186.4 - 191.2, accuracy: 0.0001)
        XCTAssertEqual(i.challenge?.goalProgress ?? 0, 0.48, accuracy: 0.0001)
        XCTAssertEqual(i.challenge?.timeProgress ?? 0, 0.6, accuracy: 0.0001)
    }

    func testStaleInsightsResetTodayOnly() {
        let i = insights(at: date(18, 21))
        // Same app day (2 AM): untouched.
        XCTAssertEqual(i.display(now: date(19, 2), calendar: calendar), i)

        let fresh = i.display(now: date(19, 7), calendar: calendar)
        XCTAssertEqual(fresh.steps, 0)
        XCTAssertNil(fresh.score)
        XCTAssertEqual(fresh.stepsWeek.count, 7)
        XCTAssertEqual(fresh.stepsWeek.last, 0)
        XCTAssertEqual(fresh.stepsWeek.first, i.stepsWeek[1])
        XCTAssertEqual(fresh.waterWeek.last, 0)
        // Last night's sleep, weight and the challenge carry over.
        XCTAssertEqual(fresh.sleepHours, i.sleepHours)
        XCTAssertEqual(fresh.weight, i.weight)
        XCTAssertEqual(fresh.challenge, i.challenge)
    }

    // MARK: - Links

    func testWidgetLinksRoundTrip() {
        for link in WidgetLink.allCases {
            XCTAssertEqual(WidgetLink(url: link.url), link)
        }
        XCTAssertEqual(WidgetLink.weighIn.url.absoluteString, "dialed://weigh-in")
        XCTAssertNil(WidgetLink(url: URL(string: "https://water")!))
        XCTAssertNil(WidgetLink(url: URL(string: "dialed://nowhere")!))
    }

    func testLogicalDayUsesFourAMCutoff() {
        XCTAssertEqual(WidgetBridge.logicalDay(for: date(19, 3, 59), calendar: calendar),
                       calendar.startOfDay(for: date(18, 12)))
        XCTAssertEqual(WidgetBridge.logicalDay(for: date(19, 4), calendar: calendar),
                       calendar.startOfDay(for: date(19, 12)))
    }
}
