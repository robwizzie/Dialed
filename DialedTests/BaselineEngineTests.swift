//
//  BaselineEngineTests.swift
//  DialedTests
//
//  Pure-math tests for the rolling baseline engine. No SwiftData here —
//  the orchestration path is exercised separately via integration tests
//  once the sync flow is wired up.
//

import XCTest
@testable import Dialed

final class BaselineEngineTests: XCTestCase {

    // MARK: - mean

    func testMean_emptyReturnsNil() {
        XCTAssertNil(BaselineEngine.mean([]))
    }

    func testMean_singleValue() {
        XCTAssertEqual(BaselineEngine.mean([42])!, 42, accuracy: 1e-9)
    }

    func testMean_multipleValues() {
        XCTAssertEqual(BaselineEngine.mean([1, 2, 3, 4, 5])!, 3, accuracy: 1e-9)
    }

    // MARK: - stdDev

    func testStdDev_lessThanTwoValuesReturnsNil() {
        XCTAssertNil(BaselineEngine.stdDev([]))
        XCTAssertNil(BaselineEngine.stdDev([5]))
    }

    func testStdDev_knownSample() {
        // Sample std dev of [2, 4, 4, 4, 5, 5, 7, 9] is exactly 2.0
        // (variance = 32/7? actually: mean=5, variance = (9+1+1+1+0+0+4+16)/7 = 32/7 ≈ 4.57)
        // Sample std dev = sqrt(32/7) ≈ 2.138
        let sd = BaselineEngine.stdDev([2, 4, 4, 4, 5, 5, 7, 9])!
        XCTAssertEqual(sd, sqrt(32.0 / 7.0), accuracy: 1e-6)
    }

    func testStdDev_identicalValuesIsZero() {
        XCTAssertEqual(BaselineEngine.stdDev([7, 7, 7, 7])!, 0, accuracy: 1e-9)
    }

    // MARK: - median

    func testMedian_emptyReturnsNil() {
        XCTAssertNil(BaselineEngine.median([]))
    }

    func testMedian_oddCount() {
        XCTAssertEqual(BaselineEngine.median([3, 1, 2])!, 2, accuracy: 1e-9)
    }

    func testMedian_evenCountAverages() {
        XCTAssertEqual(BaselineEngine.median([1, 2, 3, 4])!, 2.5, accuracy: 1e-9)
    }

    // MARK: - medianBedtimeSeconds (wrap-around)

    func testMedianBedtime_groupsAroundMidnightCorrectly() {
        // Bedtimes: 23:50, 00:10, 23:55 — should average to about 00:00, not 12:00.
        let dates = [
            date(hour: 23, minute: 50),
            date(hour: 0, minute: 10),
            date(hour: 23, minute: 55)
        ]
        let seconds = BaselineEngine.medianBedtimeSeconds(from: dates)!

        // Median in shifted space: [23:50, 23:55, 24:10] → 23:55 → mod 86400 = 23:55:00 = 86100s
        XCTAssertEqual(seconds, 23 * 3600 + 55 * 60)
    }

    func testMedianBedtime_allBeforeMidnight() {
        let dates = [
            date(hour: 22, minute: 0),
            date(hour: 22, minute: 30),
            date(hour: 23, minute: 0)
        ]
        let seconds = BaselineEngine.medianBedtimeSeconds(from: dates)!
        XCTAssertEqual(seconds, 22 * 3600 + 30 * 60)
    }

    func testMedianBedtime_emptyReturnsNil() {
        XCTAssertNil(BaselineEngine.medianBedtimeSeconds(from: []))
    }

    // MARK: - medianWakeTimeSeconds

    func testMedianWake_typicalRange() {
        let dates = [
            date(hour: 6, minute: 30),
            date(hour: 7, minute: 15),
            date(hour: 8, minute: 0)
        ]
        let seconds = BaselineEngine.medianWakeTimeSeconds(from: dates)!
        XCTAssertEqual(seconds, 7 * 3600 + 15 * 60)
    }

    // MARK: - compute (full aggregate)

    func testCompute_emptyInputProducesEmptyBaseline() {
        let computed = BaselineEngine.compute(sleepSessions: [], biometrics: [])
        XCTAssertNil(computed.restingHRMean)
        XCTAssertNil(computed.hrvMean)
        XCTAssertNil(computed.sleepDurationMean)
        XCTAssertNil(computed.bedtimeSeconds)
        XCTAssertEqual(computed.sampleDays, 0)
    }

    func testCompute_picksDominantHRVKind() {
        let bios: [BiometricSnapshot] = [
            makeBio(hrv: 40, kind: .rmssd),
            makeBio(hrv: 45, kind: .rmssd),
            makeBio(hrv: 50, kind: .sdnn)
        ]
        let computed = BaselineEngine.compute(sleepSessions: [], biometrics: bios)
        XCTAssertEqual(computed.hrvKind, .rmssd)
        XCTAssertEqual(computed.hrvMean!, 45, accuracy: 1e-6)
    }

    func testCompute_sleepStatsMatchInputs() {
        let sessions = (0..<5).map { i in
            makeSleep(asleepMin: 420 + i * 10, deepMin: 80, remMin: 90, efficiency: 0.85)
        }
        let computed = BaselineEngine.compute(sleepSessions: sessions, biometrics: [])
        XCTAssertEqual(computed.sleepDurationMean!, 440, accuracy: 1e-6)  // (420+430+440+450+460)/5
        XCTAssertEqual(computed.deepMean!, 80, accuracy: 1e-6)
        XCTAssertEqual(computed.efficiencyMean!, 0.85, accuracy: 1e-6)
        XCTAssertEqual(computed.sampleDays, 5)
    }

    // MARK: - Helpers

    private func date(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 15
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }

    private func makeBio(hrv: Double, kind: BiometricSnapshot.HRVKind) -> BiometricSnapshot {
        BiometricSnapshot(
            timestamp: Date(),
            source: .fitbit,
            hrv: hrv,
            hrvKind: kind
        )
    }

    private func makeSleep(asleepMin: Int, deepMin: Int?, remMin: Int?, efficiency: Double?) -> SleepSession {
        let now = Date()
        let s = SleepSession(
            startTime: now.addingTimeInterval(-Double(asleepMin * 60)),
            endTime: now,
            inBedMinutes: asleepMin + 20,
            asleepMinutes: asleepMin,
            source: .fitbit
        )
        s.deepMinutes = deepMin
        s.remMinutes = remMin
        s.efficiency = efficiency
        return s
    }
}
