//
//  StateEngineTests.swift
//  DialedTests
//
//  Pure-math tests for the four state pillars and their helpers. These
//  tests fix the contract — if you change a weight, you change a test.
//

import XCTest
@testable import Dialed

final class StateEngineTests: XCTestCase {

    // MARK: - Circadian curve

    func testCircadianCurve_isLowAtDeepNight() {
        let v = StateEngine.circadianCurve(at: makeTime(hour: 3))
        XCTAssertLessThan(v, 0.3, "Deep night should be a low alertness band")
    }

    func testCircadianCurve_peaksMidMorning() {
        let v = StateEngine.circadianCurve(at: makeTime(hour: 10))
        XCTAssertGreaterThan(v, 0.7, "10am should be near the alertness peak")
    }

    func testCircadianCurve_hasPostLunchDip() {
        let peak = StateEngine.circadianCurve(at: makeTime(hour: 10))
        let dip = StateEngine.circadianCurve(at: makeTime(hour: 14))
        XCTAssertLessThan(dip, peak, "Post-lunch dip should be below morning peak")
    }

    func testCircadianCurve_climbsBackInAfternoon() {
        let dip = StateEngine.circadianCurve(at: makeTime(hour: 14))
        let afternoon = StateEngine.circadianCurve(at: makeTime(hour: 17))
        XCTAssertGreaterThan(afternoon, dip)
    }

    func testCircadianCurve_dropsAfterTen() {
        let evening = StateEngine.circadianCurve(at: makeTime(hour: 19))
        let lateNight = StateEngine.circadianCurve(at: makeTime(hour: 23))
        XCTAssertLessThan(lateNight, evening)
    }

    func testCircadianBand_returnsHumanLabels() {
        XCTAssertEqual(StateEngine.circadianBand(at: makeTime(hour: 3)), "Deep night")
        XCTAssertEqual(StateEngine.circadianBand(at: makeTime(hour: 9)), "Morning peak")
        XCTAssertEqual(StateEngine.circadianBand(at: makeTime(hour: 14)), "Post-lunch dip")
        XCTAssertEqual(StateEngine.circadianBand(at: makeTime(hour: 17)), "Afternoon peak")
    }

    // MARK: - Caffeine half-life

    func testActiveCaffeine_unchangedAtTimeZero() {
        let dosed = makeTime(hour: 8)
        let active = StateEngine.activeCaffeine(doseMG: 200, dosedAt: dosed, now: dosed)
        XCTAssertEqual(active, 200, accuracy: 0.5)
    }

    func testActiveCaffeine_halvesAtFiveHours() {
        let dosed = makeTime(hour: 8)
        let later = makeTime(hour: 13)  // exactly 5h later
        let active = StateEngine.activeCaffeine(doseMG: 200, dosedAt: dosed, now: later)
        XCTAssertEqual(active, 100, accuracy: 1.0)
    }

    func testActiveCaffeine_tinyResidualAfterMuchLater() {
        let dosed = makeTime(hour: 8)
        let next = makeTime(hour: 23)  // 15h later → ~12.5mg
        let active = StateEngine.activeCaffeine(doseMG: 200, dosedAt: dosed, now: next)
        XCTAssertLessThan(active, 30)
    }

    // MARK: - Recovery

    func testRecovery_neutralWhenNoData() {
        let inputs = StateEngine.LiveInputs(now: makeTime(hour: 9))
        let r = StateEngine.recovery(inputs)
        XCTAssertEqual(r.score, 50, "No data → neutral 50")
        XCTAssertTrue(r.contributions.isEmpty)
        XCTAssertLessThan(r.confidence, 0.6)
    }

    func testRecovery_strongSleepImprovesScore() {
        let sleep = StateEngine.SleepInputs(
            asleepMinutes: 480, deepMinutes: 90, remMinutes: 110,
            efficiency: 0.92, endTime: makeTime(hour: 7),
            avgRestingHR: 52, avgHRV: 65
        )
        let baseline = StateEngine.BaselineInputs(
            restingHRMean: 55, restingHRStdDev: 4,
            hrvMean: 55, hrvStdDev: 8,
            sleepDurationMinutesMean: 450, sleepDurationMinutesStdDev: 30
        )
        let inputs = StateEngine.LiveInputs(now: makeTime(hour: 8), baseline: baseline, lastSleep: sleep)
        let r = StateEngine.recovery(inputs)
        XCTAssertGreaterThan(r.score, 75, "Long sleep + good efficiency + above-baseline HRV → high recovery")
    }

    func testRecovery_poorSleepHurtsScore() {
        let sleep = StateEngine.SleepInputs(
            asleepMinutes: 300, deepMinutes: 30, remMinutes: 40,
            efficiency: 0.6, endTime: makeTime(hour: 5),
            avgRestingHR: 70, avgHRV: 30
        )
        let baseline = StateEngine.BaselineInputs(
            restingHRMean: 55, restingHRStdDev: 4,
            hrvMean: 55, hrvStdDev: 8,
            sleepDurationMinutesMean: 450, sleepDurationMinutesStdDev: 30
        )
        let inputs = StateEngine.LiveInputs(now: makeTime(hour: 8), baseline: baseline, lastSleep: sleep)
        let r = StateEngine.recovery(inputs)
        XCTAssertLessThan(r.score, 40)
    }

    // MARK: - Readiness

    func testReadiness_tracksRecovery() {
        let highRecovery = StateEngine.readiness(.init(now: makeTime(hour: 8)), recoveryScore: 90)
        let lowRecovery = StateEngine.readiness(.init(now: makeTime(hour: 8)), recoveryScore: 30)
        XCTAssertGreaterThan(highRecovery.score, lowRecovery.score)
    }

    func testReadiness_recentStrainPenalty() {
        let fresh = StateEngine.readiness(.init(now: makeTime(hour: 8)), recoveryScore: 70, recentStrain: 0)
        let cooked = StateEngine.readiness(.init(now: makeTime(hour: 8)), recoveryScore: 70, recentStrain: 90)
        XCTAssertGreaterThan(fresh.score, cooked.score)
    }

    // MARK: - Energy

    func testEnergy_higherWithCaffeineOnBoard() {
        let base = StateEngine.energy(.init(now: makeTime(hour: 10)), recoveryScore: 70)
        let caffeinated = StateEngine.energy(
            .init(
                now: makeTime(hour: 10),
                energyContext: StateEngine.EnergyContext(activeCaffeineMG: 200)
            ),
            recoveryScore: 70
        )
        XCTAssertGreaterThan(caffeinated.score, base.score)
    }

    func testEnergy_postWorkoutDipApplied() {
        let normal = StateEngine.energy(.init(now: makeTime(hour: 16)), recoveryScore: 70)
        let postWorkout = StateEngine.energy(
            .init(
                now: makeTime(hour: 16),
                energyContext: StateEngine.EnergyContext(minutesSinceWorkout: 15)
            ),
            recoveryScore: 70
        )
        XCTAssertGreaterThan(normal.score, postWorkout.score)
    }

    func testEnergy_lowerAtDeepNight() {
        let morning = StateEngine.energy(.init(now: makeTime(hour: 10)), recoveryScore: 70)
        let night = StateEngine.energy(.init(now: makeTime(hour: 2)), recoveryScore: 70)
        XCTAssertGreaterThan(morning.score, night.score)
    }

    // MARK: - Strain

    func testStrain_zeroWithNoActivity() {
        let s = StateEngine.strain(.init(now: makeTime(hour: 9)))
        XCTAssertEqual(s.score, 0)
    }

    func testStrain_climbsWithActivity() {
        let inputs = StateEngine.LiveInputs(
            now: makeTime(hour: 20),
            dayLoad: StateEngine.DayLoadInputs(
                steps: 12_000,
                activeCalories: 600,
                exerciseMinutes: 45,
                workoutDurationMinutes: 60,
                workoutIntensity: 0.7
            )
        )
        let s = StateEngine.strain(inputs)
        XCTAssertGreaterThan(s.score, 50)
        XCTAssertLessThanOrEqual(s.score, 100)
    }

    func testStrain_capsAt100() {
        let inputs = StateEngine.LiveInputs(
            now: makeTime(hour: 20),
            dayLoad: StateEngine.DayLoadInputs(
                steps: 30_000,
                activeCalories: 2_000,
                exerciseMinutes: 180,
                workoutDurationMinutes: 180,
                workoutIntensity: 1.0
            )
        )
        let s = StateEngine.strain(inputs)
        XCTAssertEqual(s.score, 100)
    }

    // MARK: - Grade mapping

    func testGrade_mapping() {
        XCTAssertEqual(StateEngine.ScoreBreakdown.Grade(score: 92), .excellent)
        XCTAssertEqual(StateEngine.ScoreBreakdown.Grade(score: 78), .good)
        XCTAssertEqual(StateEngine.ScoreBreakdown.Grade(score: 60), .fair)
        XCTAssertEqual(StateEngine.ScoreBreakdown.Grade(score: 45), .low)
        XCTAssertEqual(StateEngine.ScoreBreakdown.Grade(score: 20), .poor)
    }

    // MARK: - Helpers

    private func makeTime(hour: Int, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 15
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }
}
