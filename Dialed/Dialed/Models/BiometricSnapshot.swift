//
//  BiometricSnapshot.swift
//  Dialed
//
//  A point-in-time biometric reading (Fitbit hourly pulls, HealthKit samples,
//  on-demand spot checks). Used to build the moment-to-moment state on the
//  Now screen and feed the Readiness/Recovery/Energy/Strain calculators.
//

import Foundation
import SwiftData

@Model
final class BiometricSnapshot {
    @Attribute(.unique) var id: UUID

    var timestamp: Date
    var logicalDate: Date

    /// Where this came from. Used to disambiguate Apple Watch vs Fitbit readings
    /// when both sources exist at the same time.
    var sourceRaw: String

    /// External ID from the source — Fitbit intraday timestamp, HKSample UUID.
    /// Used for dedup on re-sync.
    var sourceExternalID: String?

    // MARK: - Cardiovascular
    var heartRate: Double?           // bpm, instantaneous
    var restingHeartRate: Double?    // bpm, daily resting estimate
    var hrv: Double?                 // ms (SDNN or RMSSD — store unit hint below)
    var hrvKind: String?             // "sdnn" / "rmssd"

    // MARK: - Respiratory
    var spO2: Double?                // %
    var breathingRate: Double?       // bpm

    // MARK: - Thermal
    var skinTemperatureDelta: Double?  // °C from personal baseline
    var bodyTemperature: Double?       // °C absolute (rare)

    // MARK: - Derived / vendor scores
    /// Fitbit Daily Readiness Score (0–100) when available (requires Premium).
    var readinessScore: Int?

    /// Fitbit Stress Management Score / similar (0–100).
    var stressScore: Int?

    /// Estimated steps as of this snapshot (rolling intraday).
    var stepsSoFar: Int?

    var createdAt: Date

    init(
        timestamp: Date,
        source: Source,
        sourceExternalID: String? = nil,
        heartRate: Double? = nil,
        restingHeartRate: Double? = nil,
        hrv: Double? = nil,
        hrvKind: HRVKind? = nil,
        spO2: Double? = nil,
        breathingRate: Double? = nil,
        skinTemperatureDelta: Double? = nil,
        bodyTemperature: Double? = nil,
        readinessScore: Int? = nil,
        stressScore: Int? = nil,
        stepsSoFar: Int? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.logicalDate = ContextEvent.logicalDate(for: timestamp)
        self.sourceRaw = source.rawValue
        self.sourceExternalID = sourceExternalID
        self.heartRate = heartRate
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
        self.hrvKind = hrvKind?.rawValue
        self.spO2 = spO2
        self.breathingRate = breathingRate
        self.skinTemperatureDelta = skinTemperatureDelta
        self.bodyTemperature = bodyTemperature
        self.readinessScore = readinessScore
        self.stressScore = stressScore
        self.stepsSoFar = stepsSoFar
        self.createdAt = Date()
    }

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .fitbit }
        set { sourceRaw = newValue.rawValue }
    }
}

extension BiometricSnapshot {
    enum Source: String, Codable {
        case fitbit
        case healthkit
        case manual
    }

    enum HRVKind: String, Codable {
        case sdnn   // standard deviation of NN intervals (HealthKit default)
        case rmssd  // root mean square of successive differences (Fitbit default)
    }
}
