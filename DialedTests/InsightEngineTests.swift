//
//  InsightEngineTests.swift
//  DialedTests
//
//  Tests each rule in isolation (pure functions) plus an integration
//  test that runs the full pass against an in-memory store.
//

import XCTest
import SwiftData
@testable import Dialed

@MainActor
final class InsightEngineTests: XCTestCase {

    private let cal = Calendar.current
    private let dayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_716_624_000))

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ContextEvent.self,
                SleepSession.self,
                PersonalBaseline.self,
                BiometricSnapshot.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeBaseline(
        deepMinutes: Double = 90,
        remMinutes: Double = 110,
        sleepEfficiency: Double = 0.92
    ) -> PersonalBaseline {
        let b = PersonalBaseline(date: dayStart)
        b.deepMinutesMean = deepMinutes
        b.remMinutesMean = remMinutes
        b.sleepEfficiencyMean = sleepEfficiency
        return b
    }

    private func makeSleep(
        startHour: Int = 23,
        durationHours: Double = 8,
        deep: Int = 60,
        rem: Int = 70,
        efficiency: Double = 0.85
    ) -> SleepSession {
        // Sleep started on `dayStart` evening, ended on the next morning.
        let start = cal.date(byAdding: .hour, value: startHour, to: dayStart)!
        let end = start.addingTimeInterval(durationHours * 3600)
        let session = SleepSession(
            startTime: start,
            endTime: end,
            inBedMinutes: Int(durationHours * 60),
            asleepMinutes: Int(durationHours * 60 * efficiency),
            source: .manual
        )
        session.deepMinutes = deep
        session.remMinutes = rem
        session.efficiency = efficiency
        return session
    }

    // MARK: - LateCaffeineRule

    func testLateCaffeineRule_annotatesWhenLateCoffeeAndEfficiencyDrop() {
        let baseline = makeBaseline(sleepEfficiency: 0.92)
        // Efficiency 0.85 = 7pp below baseline (>4pp threshold)
        let sleep = makeSleep(efficiency: 0.85)
        let lateCoffee = ContextEvent.caffeine(
            milligrams: 150,
            subtype: "coffee",
            at: cal.date(byAdding: .hour, value: 15, to: dayStart)!
        )

        let outputs = LateCaffeineRule().apply(
            events: [lateCoffee],
            nextNightSleep: sleep,
            baseline: baseline
        )

        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(outputs[0].annotation.contains("Sleep efficiency dropped"))
        XCTAssertTrue(outputs[0].annotation.contains("7 pts"))
    }

    func testLateCaffeineRule_noAnnotationWhenCoffeeWasEarly() {
        let baseline = makeBaseline(sleepEfficiency: 0.92)
        let sleep = makeSleep(efficiency: 0.85)  // drop exists
        let earlyCoffee = ContextEvent.caffeine(
            milligrams: 150, subtype: "coffee",
            at: cal.date(byAdding: .hour, value: 7, to: dayStart)!  // 7 AM
        )
        let outputs = LateCaffeineRule().apply(
            events: [earlyCoffee],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertTrue(outputs.isEmpty, "Early caffeine should not be annotated")
    }

    func testLateCaffeineRule_noAnnotationWhenEfficiencyDropTooSmall() {
        let baseline = makeBaseline(sleepEfficiency: 0.92)
        // Only 1pp drop → below 4pp threshold.
        let sleep = makeSleep(efficiency: 0.91)
        let lateCoffee = ContextEvent.caffeine(
            milligrams: 150, subtype: "coffee",
            at: cal.date(byAdding: .hour, value: 16, to: dayStart)!
        )
        let outputs = LateCaffeineRule().apply(
            events: [lateCoffee],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertTrue(outputs.isEmpty)
    }

    func testLateCaffeineRule_picksLatestCaffeineWhenMultiple() {
        let baseline = makeBaseline(sleepEfficiency: 0.92)
        let sleep = makeSleep(efficiency: 0.84)
        let firstLate = ContextEvent.caffeine(milligrams: 95, subtype: "coffee",
            at: cal.date(byAdding: .hour, value: 14, to: dayStart)!)
        let secondLate = ContextEvent.caffeine(milligrams: 200, subtype: "preworkout",
            at: cal.date(byAdding: .hour, value: 17, to: dayStart)!)
        let outputs = LateCaffeineRule().apply(
            events: [firstLate, secondLate],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(outputs[0].event === secondLate, "Should annotate the latest late caffeine")
    }

    // MARK: - LateMealRule

    func testLateMealRule_annotatesLargeMealCloseToBedAndREMDrop() {
        let baseline = makeBaseline(remMinutes: 110)
        let sleep = makeSleep(rem: 80)  // 30 min REM drop (>20 threshold)

        // Sleep starts at 23:00 on dayStart; cutoff = 20:00.
        let meal = ContextEvent.meal(
            calories: 700, protein: 40,
            at: cal.date(byAdding: .hour, value: 21, to: dayStart)!  // 9 PM
        )

        let outputs = LateMealRule().apply(
            events: [meal],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(outputs[0].annotation.contains("REM dropped 30 min"))
    }

    func testLateMealRule_noAnnotationWhenMealIsBeforeWindow() {
        let baseline = makeBaseline(remMinutes: 110)
        let sleep = makeSleep(rem: 80)  // drop exists
        // Sleep starts at 23:00, cutoff = 20:00. A meal at 19:00 is outside.
        let earlyDinner = ContextEvent.meal(
            calories: 700, protein: 40,
            at: cal.date(byAdding: .hour, value: 19, to: dayStart)!
        )
        let outputs = LateMealRule().apply(
            events: [earlyDinner],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertTrue(outputs.isEmpty)
    }

    func testLateMealRule_noAnnotationWhenMealTooSmall() {
        let baseline = makeBaseline(remMinutes: 110)
        let sleep = makeSleep(rem: 80)
        let lightSnack = ContextEvent.meal(
            calories: 200, protein: 10,
            at: cal.date(byAdding: .hour, value: 22, to: dayStart)!
        )
        let outputs = LateMealRule().apply(
            events: [lightSnack],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertTrue(outputs.isEmpty, "Sub-500-kcal meals don't trigger the rule")
    }

    func testLateMealRule_noAnnotationWhenREMDropTooSmall() {
        let baseline = makeBaseline(remMinutes: 110)
        let sleep = makeSleep(rem: 105)  // only 5 min drop
        let lateMeal = ContextEvent.meal(
            calories: 700, protein: 40,
            at: cal.date(byAdding: .hour, value: 21, to: dayStart)!
        )
        let outputs = LateMealRule().apply(
            events: [lateMeal],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertTrue(outputs.isEmpty)
    }

    // MARK: - AlcoholRule

    func testAlcoholRule_annotatesWhenDeepSleepDropsOverThreshold() {
        let baseline = makeBaseline(deepMinutes: 90)
        let sleep = makeSleep(deep: 60)  // 33% drop
        let drinks = ContextEvent.alcohol(
            standardDrinks: 2,
            at: cal.date(byAdding: .hour, value: 20, to: dayStart)!
        )
        let outputs = AlcoholRule().apply(
            events: [drinks],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(outputs[0].annotation.contains("Deep sleep dropped"))
        XCTAssertTrue(outputs[0].annotation.contains("33%"))
    }

    func testAlcoholRule_noAnnotationWhenDeepSleepHoldsUp() {
        let baseline = makeBaseline(deepMinutes: 90)
        let sleep = makeSleep(deep: 85)  // ~5% drop
        let drinks = ContextEvent.alcohol(
            standardDrinks: 2,
            at: cal.date(byAdding: .hour, value: 20, to: dayStart)!
        )
        let outputs = AlcoholRule().apply(
            events: [drinks],
            nextNightSleep: sleep,
            baseline: baseline
        )
        XCTAssertTrue(outputs.isEmpty)
    }

    func testAlcoholRule_noAnnotationWithoutBaseline() {
        let sleep = makeSleep(deep: 40)
        let drinks = ContextEvent.alcohol(standardDrinks: 3, at: dayStart)
        let outputs = AlcoholRule().apply(
            events: [drinks],
            nextNightSleep: sleep,
            baseline: nil
        )
        XCTAssertTrue(outputs.isEmpty, "Without baseline we have nothing to compare against")
    }

    // MARK: - Integration: runDailyPass

    func testRunDailyPass_endToEndWritesAnnotation() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Seed baseline (most recent date).
        let baseline = makeBaseline(deepMinutes: 90, remMinutes: 110, sleepEfficiency: 0.92)
        context.insert(baseline)

        // Day X = dayStart. Insert a late coffee on day X.
        let lateCoffee = ContextEvent.caffeine(
            milligrams: 150, subtype: "coffee",
            at: cal.date(byAdding: .hour, value: 16, to: dayStart)!
        )
        context.insert(lateCoffee)

        // Insert sleep that started day X evening and ended day X+1 morning
        // → logicalDate = day X+1.
        let sleep = makeSleep(efficiency: 0.83)  // 9pp drop
        context.insert(sleep)
        try context.save()

        InsightEngine.runDailyPass(for: dayStart, context: context)

        // Re-fetch and verify the annotation was persisted.
        let refetched = (try? context.fetch(FetchDescriptor<ContextEvent>()))?.first
        XCTAssertNotNil(refetched?.aiAnnotation,
                        "Late caffeine on day X should pick up an annotation after the daily pass")
        XCTAssertTrue(refetched?.aiAnnotation?.contains("Sleep efficiency dropped") ?? false)
    }

    func testRunDailyPass_isIdempotentAndOverwritesStaleAnnotations() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Run with one set of facts → annotation written.
        let baseline = makeBaseline(sleepEfficiency: 0.92)
        context.insert(baseline)
        let lateCoffee = ContextEvent.caffeine(
            milligrams: 150, subtype: "coffee",
            at: cal.date(byAdding: .hour, value: 16, to: dayStart)!
        )
        context.insert(lateCoffee)
        let sleep = makeSleep(efficiency: 0.83)
        context.insert(sleep)
        try context.save()
        InsightEngine.runDailyPass(for: dayStart, context: context)
        XCTAssertNotNil(lateCoffee.aiAnnotation)

        // Now "improve" the sleep — efficiency above baseline. Re-running
        // should CLEAR the stale annotation since the rule no longer
        // matches.
        sleep.efficiency = 0.95
        try context.save()
        InsightEngine.runDailyPass(for: dayStart, context: context)
        XCTAssertNil(lateCoffee.aiAnnotation,
                     "Stale annotations should be wiped when the rule no longer matches")
    }
}
