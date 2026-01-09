//
//  ScoringEngine.swift
//  Dialed
//
//  Pure functions for calculating sleep scores and daily scores
//  100% testable, no side effects
//

import Foundation

struct ScoringEngine {

    // MARK: - Sleep Score Calculation (Automated from RingConn/HealthKit)

    /// Calculate sleep score from objective metrics (0-5)
    /// - Parameters:
    ///   - totalSleepMinutes: Total sleep duration
    ///   - deepSleepMinutes: Deep sleep duration
    ///   - remSleepMinutes: REM sleep duration
    ///   - awakeDurationMinutes: Time awake during sleep period
    ///   - timeInBedMinutes: Total time in bed
    ///   - hrv: Heart rate variability (optional)
    ///   - restingHR: Resting heart rate (optional)
    /// - Returns: Sleep score 0-5 (in 0.5 increments)
    static func calculateSleepScore(
        totalSleepMinutes: Int,
        deepSleepMinutes: Int? = nil,
        remSleepMinutes: Int? = nil,
        awakeDurationMinutes: Int? = nil,
        timeInBedMinutes: Int? = nil,
        hrv: Double? = nil,
        restingHR: Double? = nil
    ) -> Int {
        var score = 0.0

        // 1. Duration score (0-2 points)
        // Target: 7-9 hours optimal, 6-7 decent, 5-6 okay
        let hours = Double(totalSleepMinutes) / 60.0
        if hours >= Constants.Sleep.optimalDurationMin && hours <= Constants.Sleep.optimalDurationMax {
            score += 2.0  // Perfect duration
        } else if hours >= 6.0 && hours < Constants.Sleep.optimalDurationMin {
            score += 1.5  // Decent
        } else if hours >= 5.0 && hours < 6.0 {
            score += 1.0  // Okay but low
        } else if hours > Constants.Sleep.optimalDurationMax && hours <= 10.0 {
            score += 1.5  // Slightly over is fine
        } else {
            score += 0.5  // Too short or too long
        }

        // 2. Sleep efficiency (0-1.5 points)
        // Efficiency = time asleep / time in bed
        // Target: >85% = excellent
        if let timeInBed = timeInBedMinutes, timeInBed > 0 {
            let efficiency = Double(totalSleepMinutes) / Double(timeInBed)
            if efficiency >= Constants.Sleep.optimalEfficiency {
                score += 1.5  // Excellent efficiency
            } else if efficiency >= 0.75 {
                score += 1.0  // Good
            } else if efficiency >= 0.65 {
                score += 0.5  // Fair
            }
        } else {
            // If we don't have time in bed data, give benefit of the doubt
            score += 1.0
        }

        // 3. Deep sleep quality (0-1.5 points)
        // Target: 15-25% of total sleep is deep sleep
        if let deepMinutes = deepSleepMinutes, totalSleepMinutes > 0 {
            let deepPercentage = Double(deepMinutes) / Double(totalSleepMinutes)
            if deepPercentage >= Constants.Sleep.optimalDeepSleepMin &&
               deepPercentage <= Constants.Sleep.optimalDeepSleepMax {
                score += 1.5  // Optimal deep sleep
            } else if deepPercentage >= 0.10 && deepPercentage < Constants.Sleep.optimalDeepSleepMin {
                score += 1.0  // Decent
            } else if deepPercentage >= 0.08 {
                score += 0.5  // Low but present
            }
        } else {
            // If no deep sleep data, give partial credit
            score += 0.75
        }

        // 4. HRV bonus (0-0.5 points)
        // Higher HRV generally = better recovery
        // This is user-specific, but >50ms is generally good
        if let hrvValue = hrv {
            if hrvValue >= Constants.Sleep.goodHRVThreshold {
                score += 0.5
            } else if hrvValue >= 30 {
                score += 0.25
            }
        }

        // Cap at 5.0 and round to nearest 0.5
        let cappedScore = min(score, 5.0)
        let roundedScore = (cappedScore * 2).rounded() / 2

        // Convert to Int (0-5 scale, stored as 0, 1, 2, 3, 4, 5)
        return Int(roundedScore)
    }

    // MARK: - Daily Score Calculation (0-100 points)

    /// Calculate the daily score from all metrics
    /// - Parameters:
    ///   - protein: Protein consumed (grams)
    ///   - proteinTarget: Protein target (grams)
    ///   - workoutCompleted: Was workout detected/logged?
    ///   - workoutScore: Workout quality (0-5), nil if no workout
    ///   - mileCompleted: Was mile completed?
    ///   - mileScore: Mile quality (0-5), nil if no mile
    ///   - sleepScore: Calculated sleep score (0-5)
    ///   - sleepDurationMinutes: Sleep duration for bonus points
    ///   - water: Water consumed (oz)
    ///   - waterTarget: Water target (oz)
    ///   - checklistCompletion: Checklist item statuses
    /// - Returns: Daily score (0-100)
    static func calculateDailyScore(
        protein: Double,
        proteinTarget: Double,
        workoutCompleted: Bool,
        workoutScore: Int?,
        mileCompleted: Bool,
        mileScore: Int?,
        sleepScore: Int?,
        sleepDurationMinutes: Int?,
        water: Double,
        waterTarget: Double,
        checklistCompletion: [String: Bool]  // ChecklistType.rawValue: completed
    ) -> Int {
        var totalScore = 0.0

        // 1. Protein adherence (25 points max)
        let proteinRatio = min(protein / proteinTarget, 1.0)
        var proteinPoints = Double(Constants.Scoring.proteinWeight) * proteinRatio

        // Bonus: if hit target exactly or above, +2 bonus
        if protein >= proteinTarget {
            proteinPoints += 2.0
        }

        // Cap protein section at 27 (25 base + 2 bonus)
        proteinPoints = min(proteinPoints, 27.0)
        totalScore += proteinPoints

        // 2. Workout completion (10 points) + quality (10 points) = 20 total
        if workoutCompleted {
            totalScore += Double(Constants.Scoring.workoutCompletionWeight)  // 10 pts base

            // Workout quality: 0-5 score → 0-10 points (multiply by 2)
            if let quality = workoutScore {
                let qualityPoints = Double(quality) * 2.0
                totalScore += qualityPoints
            } else {
                // If workout completed but no quality score, give default 6 points (3/5 quality)
                totalScore += 6.0
            }
        }

        // 3. Mile completion (7 points) + quality (8 points) = 15 total
        if mileCompleted {
            totalScore += Double(Constants.Scoring.mileCompletionWeight)  // 7 pts base

            // Mile quality: 0-5 score → 0-8 points (multiply by 1.6)
            if let quality = mileScore {
                let qualityPoints = Double(quality) * 1.6
                totalScore += qualityPoints
            } else {
                // Default to 5 points if no quality score
                totalScore += 5.0
            }
        }

        // 4. Sleep (20 points total)
        // Sleep score (0-5) × 3 = 0-15 points
        // Sleep duration bonus: up to 5 points
        if let sleep = sleepScore {
            let sleepPoints = Double(sleep) * 3.0  // 0-15 points
            totalScore += sleepPoints
        }

        // Sleep duration bonus
        if let durationMin = sleepDurationMinutes {
            let hours = Double(durationMin) / 60.0
            if hours >= 7.0 {
                totalScore += 5.0  // Full bonus for 7+ hours
            } else if hours >= 6.0 {
                totalScore += 3.0
            } else if hours >= 5.0 {
                totalScore += 1.0
            }
        }

        // 5. Hydration (10 points)
        let waterRatio = min(water / waterTarget, 1.0)
        let waterPoints = Double(Constants.Scoring.hydrationWeight) * waterRatio
        totalScore += waterPoints

        // 6. Routine checklist (10 points total)
        // AM Skincare: 2pts, PM Skincare: 2pts, Lunch Vitamins: 3pts, Creatine: 3pts
        var routinePoints = 0.0

        for checklistType in Constants.ChecklistType.allCases {
            let completed = checklistCompletion[checklistType.rawValue] ?? false
            if completed {
                routinePoints += Double(checklistType.points)
            }
        }

        totalScore += routinePoints

        // Cap at 100 and round
        let finalScore = min(totalScore, 100.0).rounded()

        return Int(finalScore)
    }

    // MARK: - Helper: Calculate provisional score from DayLog

    /// Calculate provisional score from a DayLog object
    static func calculateProvisionalScore(
        from dayLog: DayLog,
        settings: UserSettings
    ) -> Int {
        // Build checklist completion dictionary
        var checklistCompletion: [String: Bool] = [:]
        if let items = dayLog.checklistItems {
            for item in items {
                checklistCompletion[item.type] = (item.checklistStatus == .done)
            }
        }

        return calculateDailyScore(
            protein: dayLog.proteinGrams,
            proteinTarget: settings.proteinTargetGrams,
            workoutCompleted: dayLog.workoutTag != nil,
            workoutScore: dayLog.workoutScore,
            mileCompleted: dayLog.mileCompleted,
            mileScore: dayLog.mileScore,
            sleepScore: dayLog.sleepScore,
            sleepDurationMinutes: dayLog.sleepDurationMinutes,
            water: dayLog.waterOz,
            waterTarget: settings.waterTargetOz,
            checklistCompletion: checklistCompletion
        )
    }
}
