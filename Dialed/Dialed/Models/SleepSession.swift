//
//  SleepSession.swift
//  Dialed
//
//  Rich sleep session — one row per night, may span midnight. Replaces the
//  sleep-related fields on DayLog (which remain populated for backward compat
//  during the migration but are sourced from the latest SleepSession going
//  forward).
//

import Foundation
import SwiftData

@Model
final class SleepSession {
    @Attribute(.unique) var id: UUID

    /// When you went to bed.
    var startTime: Date

    /// When you woke up.
    var endTime: Date

    /// The "wake day" — the DayLog date this session credits.
    /// (e.g. you slept Mon 11pm → Tue 7am; logicalDate = Tuesday.)
    var logicalDate: Date

    // MARK: - Stages (minutes)
    var inBedMinutes: Int
    var asleepMinutes: Int
    var deepMinutes: Int?
    var remMinutes: Int?
    var lightMinutes: Int?
    var awakeMinutes: Int?

    /// 0–1.0. asleep / inBed.
    var efficiency: Double?

    /// Number of awakenings.
    var awakeningCount: Int?

    // MARK: - Vendor scores
    /// Fitbit "Sleep Score" (0–100) when present.
    var vendorSleepScore: Int?

    /// Our computed sleep score (0–5) — same scale as the legacy field on DayLog
    /// so existing UI keeps working unchanged.
    var computedSleepScore: Int?

    // MARK: - Associated biometrics during the session
    var avgRestingHeartRate: Double?
    var lowestHeartRate: Double?
    var avgHRV: Double?
    var hrvKind: String?  // "sdnn" / "rmssd"
    var avgBreathingRate: Double?
    var avgSpO2: Double?
    var lowestSpO2: Double?
    var skinTemperatureDelta: Double?

    // MARK: - Provenance
    var sourceRaw: String
    var sourceExternalID: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        startTime: Date,
        endTime: Date,
        inBedMinutes: Int,
        asleepMinutes: Int,
        source: Source,
        sourceExternalID: String? = nil
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.logicalDate = Calendar.current.startOfDay(for: endTime)
        self.inBedMinutes = inBedMinutes
        self.asleepMinutes = asleepMinutes
        self.sourceRaw = source.rawValue
        self.sourceExternalID = sourceExternalID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .fitbit }
        set { sourceRaw = newValue.rawValue }
    }

    /// Convenience: fractional hours asleep.
    var hoursAsleep: Double {
        Double(asleepMinutes) / 60.0
    }

    /// Deep sleep as fraction of asleep time (0–1), or nil if unknown.
    var deepFraction: Double? {
        guard let deep = deepMinutes, asleepMinutes > 0 else { return nil }
        return Double(deep) / Double(asleepMinutes)
    }

    /// REM sleep as fraction of asleep time (0–1), or nil if unknown.
    var remFraction: Double? {
        guard let rem = remMinutes, asleepMinutes > 0 else { return nil }
        return Double(rem) / Double(asleepMinutes)
    }
}

extension SleepSession {
    enum Source: String, Codable {
        case fitbit
        case healthkit
        case manual
    }
}
