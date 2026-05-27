//
//  PersonalBaseline.swift
//  Dialed
//
//  Rolling personal baselines computed nightly. Powers the Recovery /
//  Readiness rings — every live metric is expressed as a deviation from
//  *your* baseline, not a population mean. One row per day keeps history
//  so you can see drift over months.
//

import Foundation
import SwiftData

@Model
final class PersonalBaseline {
    @Attribute(.unique) var id: UUID

    /// The date this baseline was computed for (start of day).
    var date: Date

    /// Lookback window in days. Default 28, but we may keep multiple windows
    /// per date in the future (e.g. 7-day for trend, 60-day for long term).
    var windowDays: Int

    // MARK: - Cardiovascular
    var restingHeartRateMean: Double?
    var restingHeartRateStdDev: Double?

    var hrvMean: Double?
    var hrvStdDev: Double?
    var hrvKind: String?  // "sdnn" / "rmssd"

    // MARK: - Sleep
    var sleepDurationMinutesMean: Double?   // total asleep, minutes
    var sleepDurationMinutesStdDev: Double?
    var deepMinutesMean: Double?
    var remMinutesMean: Double?
    var sleepEfficiencyMean: Double?        // 0–1

    /// Median bedtime as seconds since midnight (allows averaging across midnight).
    var bedtimeMedianSecondsFromMidnight: Int?

    /// Median wake time as seconds since midnight.
    var wakeTimeMedianSecondsFromMidnight: Int?

    // MARK: - Respiratory / thermal
    var spO2Mean: Double?
    var breathingRateMean: Double?

    // MARK: - Activity
    var dailyStepsMean: Double?
    var dailyActiveCaloriesMean: Double?

    // MARK: - Data quality
    /// How many of the last `windowDays` actually had data (0…windowDays).
    var sampleDays: Int

    var computedAt: Date

    init(date: Date, windowDays: Int = 28) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.windowDays = windowDays
        self.sampleDays = 0
        self.computedAt = Date()
    }

    // MARK: - Z-score helpers
    // Express a live reading as standard deviations from baseline.
    // Positive values mean "above your normal".

    func zScoreRestingHR(_ value: Double) -> Double? {
        guard let mean = restingHeartRateMean,
              let sd = restingHeartRateStdDev, sd > 0 else { return nil }
        return (value - mean) / sd
    }

    func zScoreHRV(_ value: Double) -> Double? {
        guard let mean = hrvMean,
              let sd = hrvStdDev, sd > 0 else { return nil }
        return (value - mean) / sd
    }

    func zScoreSleepDuration(_ minutes: Double) -> Double? {
        guard let mean = sleepDurationMinutesMean,
              let sd = sleepDurationMinutesStdDev, sd > 0 else { return nil }
        return (minutes - mean) / sd
    }

    /// Convenience: median bedtime as a wall-clock representation (hour, minute).
    var bedtimeMedianComponents: (hour: Int, minute: Int)? {
        guard let seconds = bedtimeMedianSecondsFromMidnight else { return nil }
        return (seconds / 3600, (seconds % 3600) / 60)
    }

    var wakeTimeMedianComponents: (hour: Int, minute: Int)? {
        guard let seconds = wakeTimeMedianSecondsFromMidnight else { return nil }
        return (seconds / 3600, (seconds % 3600) / 60)
    }
}
