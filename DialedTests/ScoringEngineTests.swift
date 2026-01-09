//
//  ScoringEngineTests.swift
//  DialedTests
//
//  Unit tests for scoring logic - CRITICAL to get this right!
//

import XCTest
@testable import Dialed

final class ScoringEngineTests: XCTestCase {

    // MARK: - Sleep Score Tests

    func testSleepScore_PerfectSleep() {
        // 8 hours, 90% efficiency, 20% deep sleep, good HRV
        let score = ScoringEngine.calculateSleepScore(
            totalSleepMinutes: 480,  // 8 hours
            deepSleepMinutes: 96,     // 20% deep
            remSleepMinutes: 120,
            awakeDurationMinutes: 10,
            timeInBedMinutes: 530,    // 90% efficiency
            hrv: 60,
            restingHR: 55
        )

        XCTAssertEqual(score, 5, "Perfect sleep should score 5")
    }

    func testSleepScore_DecentSleep() {
        // 6.5 hours, 75% efficiency, 12% deep sleep
        let score = ScoringEngine.calculateSleepScore(
            totalSleepMinutes: 390,  // 6.5 hours
            deepSleepMinutes: 47,     // 12% deep
            remSleepMinutes: 90,
            awakeDurationMinutes: 30,
            timeInBedMinutes: 520,    // 75% efficiency
            hrv: 45,
            restingHR: 60
        )

        XCTAssertGreaterThanOrEqual(score, 2, "Decent sleep should score at least 2")
        XCTAssertLessThanOrEqual(score, 4, "Decent sleep should score at most 4")
    }

    func testSleepScore_PoorSleep() {
        // 4 hours, low efficiency, minimal deep sleep
        let score = ScoringEngine.calculateSleepScore(
            totalSleepMinutes: 240,  // 4 hours
            deepSleepMinutes: 15,     // 6% deep
            remSleepMinutes: 30,
            awakeDurationMinutes: 60,
            timeInBedMinutes: 480,    // 50% efficiency
            hrv: 25,
            restingHR: 75
        )

        XCTAssertLessThanOrEqual(score, 2, "Poor sleep should score 2 or less")
    }

    func testSleepScore_NoOptionalData() {
        // Just duration, no other metrics
        let score = ScoringEngine.calculateSleepScore(
            totalSleepMinutes: 420  // 7 hours
        )

        XCTAssertGreaterThanOrEqual(score, 2, "Should handle missing optional data gracefully")
    }

    // MARK: - Daily Score Tests

    func testDailyScore_PerfectDay() {
        // All targets hit, all tasks complete
        let score = ScoringEngine.calculateDailyScore(
            protein: 190,
            proteinTarget: 190,
            workoutCompleted: true,
            workoutScore: 5,
            mileCompleted: true,
            mileScore: 5,
            sleepScore: 5,
            sleepDurationMinutes: 480,  // 8 hours
            water: 120,
            waterTarget: 120,
            checklistCompletion: [
                "AM Skincare": true,
                "Lunch Vitamins": true,
                "Creatine": true,
                "PM Skincare": true
            ]
        )

        XCTAssertGreaterThanOrEqual(score, 90, "Perfect day should score 90+")
        XCTAssertLessThanOrEqual(score, 100, "Score should not exceed 100")
    }

    func testDailyScore_GoodDay() {
        // Most targets hit, minor misses
        let score = ScoringEngine.calculateDailyScore(
            protein: 170,          // 89% of target
            proteinTarget: 190,
            workoutCompleted: true,
            workoutScore: 4,
            mileCompleted: true,
            mileScore: 3,
            sleepScore: 4,
            sleepDurationMinutes: 390,  // 6.5 hours
            water: 100,            // 83% of target
            waterTarget: 120,
            checklistCompletion: [
                "AM Skincare": true,
                "Lunch Vitamins": true,
                "Creatine": false,  // Missed
                "PM Skincare": true
            ]
        )

        XCTAssertGreaterThanOrEqual(score, 70, "Good day should score 70+")
        XCTAssertLessThanOrEqual(score, 89, "Good day should score below 90")
    }

    func testDailyScore_AverageDay() {
        // Some targets met, some missed
        let score = ScoringEngine.calculateDailyScore(
            protein: 140,          // 74% of target
            proteinTarget: 190,
            workoutCompleted: true,
            workoutScore: 3,
            mileCompleted: false,  // No mile
            mileScore: nil,
            sleepScore: 3,
            sleepDurationMinutes: 360,  // 6 hours
            water: 80,             // 67% of target
            waterTarget: 120,
            checklistCompletion: [
                "AM Skincare": true,
                "Lunch Vitamins": false,
                "Creatine": true,
                "PM Skincare": false
            ]
        )

        XCTAssertGreaterThanOrEqual(score, 50, "Average day should score 50+")
        XCTAssertLessThanOrEqual(score, 74, "Average day should score below 75")
    }

    func testDailyScore_PoorDay() {
        // Most targets missed
        let score = ScoringEngine.calculateDailyScore(
            protein: 80,
            proteinTarget: 190,
            workoutCompleted: false,
            workoutScore: nil,
            mileCompleted: false,
            mileScore: nil,
            sleepScore: 2,
            sleepDurationMinutes: 300,  // 5 hours
            water: 40,
            waterTarget: 120,
            checklistCompletion: [
                "AM Skincare": false,
                "Lunch Vitamins": false,
                "Creatine": false,
                "PM Skincare": true
            ]
        )

        XCTAssertLessThanOrEqual(score, 40, "Poor day should score 40 or below")
    }

    func testDailyScore_ProteinBonus() {
        // Test protein bonus when target is exceeded
        let scoreAtTarget = ScoringEngine.calculateDailyScore(
            protein: 190,
            proteinTarget: 190,
            workoutCompleted: false,
            workoutScore: nil,
            mileCompleted: false,
            mileScore: nil,
            sleepScore: 0,
            sleepDurationMinutes: 0,
            water: 0,
            waterTarget: 120,
            checklistCompletion: [:]
        )

        let scoreAboveTarget = ScoringEngine.calculateDailyScore(
            protein: 210,
            proteinTarget: 190,
            workoutCompleted: false,
            workoutScore: nil,
            mileCompleted: false,
            mileScore: nil,
            sleepScore: 0,
            sleepDurationMinutes: 0,
            water: 0,
            waterTarget: 120,
            checklistCompletion: [:]
        )

        XCTAssertGreaterThan(scoreAboveTarget, scoreAtTarget, "Exceeding protein target should give bonus points")
    }

    func testDailyScore_WorkoutWithoutQualityScore() {
        // Workout detected but no quality rating
        let score = ScoringEngine.calculateDailyScore(
            protein: 0,
            proteinTarget: 190,
            workoutCompleted: true,
            workoutScore: nil,  // No quality score
            mileCompleted: false,
            mileScore: nil,
            sleepScore: 0,
            sleepDurationMinutes: 0,
            water: 0,
            waterTarget: 120,
            checklistCompletion: [:]
        )

        // Should still get workout completion points + default quality points
        XCTAssertGreaterThanOrEqual(score, 15, "Workout without quality should still score points")
    }

    func testDailyScore_NeverExceeds100() {
        // Try to max out everything beyond 100
        let score = ScoringEngine.calculateDailyScore(
            protein: 500,  // Way over
            proteinTarget: 190,
            workoutCompleted: true,
            workoutScore: 5,
            mileCompleted: true,
            mileScore: 5,
            sleepScore: 5,
            sleepDurationMinutes: 600,  // 10 hours
            water: 200,
            waterTarget: 120,
            checklistCompletion: [
                "AM Skincare": true,
                "Lunch Vitamins": true,
                "Creatine": true,
                "PM Skincare": true
            ]
        )

        XCTAssertLessThanOrEqual(score, 100, "Score must never exceed 100")
    }

    func testDailyScore_AllZeros() {
        // Absolute worst day
        let score = ScoringEngine.calculateDailyScore(
            protein: 0,
            proteinTarget: 190,
            workoutCompleted: false,
            workoutScore: nil,
            mileCompleted: false,
            mileScore: nil,
            sleepScore: 0,
            sleepDurationMinutes: 0,
            water: 0,
            waterTarget: 120,
            checklistCompletion: [:]
        )

        XCTAssertEqual(score, 0, "All zeros should result in 0 score")
    }

    // MARK: - Integration Tests

    func testProvisionalScore_FromDayLog() {
        // Create a mock DayLog
        let dayLog = DayLog(date: Date())
        dayLog.proteinGrams = 180
        dayLog.waterOz = 110
        dayLog.workoutTag = Constants.WorkoutTag.push.rawValue
        dayLog.workoutScore = 4
        dayLog.mileCompleted = true
        dayLog.mileScore = 4
        dayLog.sleepScore = 4
        dayLog.sleepDurationMinutes = 420  // 7 hours

        // Mark some checklist items done
        if let items = dayLog.checklistItems {
            items[0].markDone()  // AM Skincare
            items[1].markDone()  // Lunch Vitamins
            items[2].markDone()  // Creatine
        }

        let settings = UserSettings.defaultSettings

        let score = ScoringEngine.calculateProvisionalScore(from: dayLog, settings: settings)

        XCTAssertGreaterThan(score, 0, "Provisional score should be calculated")
        XCTAssertLessThanOrEqual(score, 100, "Provisional score should not exceed 100")
    }
}
