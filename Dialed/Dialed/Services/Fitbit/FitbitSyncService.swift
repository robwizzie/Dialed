//
//  FitbitSyncService.swift
//  Dialed
//
//  Orchestrates a Fitbit → SwiftData sync for a given date range. Translates
//  Fitbit's wire format into our domain models (SleepSession, BiometricSnapshot).
//  Idempotent: re-syncing the same date updates rather than duplicates.
//

import Foundation
import SwiftData

@MainActor
final class FitbitSyncService: ObservableObject {
    private let api = FitbitAPIClient.shared
    private let modelContext: ModelContext

    @Published var isSyncing: Bool = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// ISO timestamp parser for Fitbit's wire format (`2026-05-25T22:34:00.000`).
    /// Note: Fitbit serves times in the user's profile timezone, no offset.
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Public entry points

    /// Sync a single date end-to-end (sleep + biometrics + activity).
    func syncDay(_ date: Date) async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            async let sleep = try api.sleep(on: date)
            async let hrv = try api.hrv(on: date)
            async let hr = try api.heartRate(on: date)
            async let spO2 = try api.spO2(on: date)
            async let br = try api.breathingRate(on: date)
            async let skin = try api.skinTemperature(on: date)

            let (sleepResp, hrvResp, hrResp, spO2Resp, brResp, skinResp) = try await (sleep, hrv, hr, spO2, br, skin)

            try ingestSleep(sleepResp, fallbackDate: date)
            try ingestDailyBiometrics(
                date: date,
                hrv: hrvResp,
                hr: hrResp,
                spO2: spO2Resp,
                br: brResp,
                skin: skinResp
            )

            lastSyncedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Backfill the last N days (used after first connect and on a manual refresh).
    func backfill(days: Int) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            await syncDay(date)
        }
    }

    // MARK: - Sleep ingestion

    private func ingestSleep(_ resp: FitbitDTO.SleepResponse, fallbackDate: Date) throws {
        for entry in resp.sleep where entry.isMainSleep {
            guard let start = Self.isoFormatter.date(from: entry.startTime),
                  let end = Self.isoFormatter.date(from: entry.endTime) else {
                continue
            }

            let externalID = String(entry.logId)

            // Dedup: replace by external ID if we've seen this Fitbit logId before.
            let descriptor = FetchDescriptor<SleepSession>(
                predicate: #Predicate { $0.sourceExternalID == externalID }
            )
            let existing = try modelContext.fetch(descriptor).first

            let session = existing ?? SleepSession(
                startTime: start,
                endTime: end,
                inBedMinutes: entry.timeInBed,
                asleepMinutes: entry.minutesAsleep,
                source: .fitbit,
                sourceExternalID: externalID
            )

            session.startTime = start
            session.endTime = end
            session.logicalDate = Calendar.current.startOfDay(for: end)
            session.inBedMinutes = entry.timeInBed
            session.asleepMinutes = entry.minutesAsleep
            session.efficiency = Double(entry.efficiency) / 100.0
            session.awakeningCount = entry.minutesAwake > 0 ? entry.minutesAfterWakeup : nil

            if let levels = entry.levels?.summary {
                session.deepMinutes = levels.deep?.minutes
                session.remMinutes = levels.rem?.minutes
                session.lightMinutes = levels.light?.minutes
                // Fitbit returns either `wake` (stages mode) or `awake` (classic).
                session.awakeMinutes = levels.wake?.minutes ?? levels.awake?.minutes
            }

            if existing == nil {
                modelContext.insert(session)
            } else {
                session.updatedAt = Date()
            }

            // Also drop a Timeline anchor event so the night shows up on the strip.
            try upsertContextAnchor(
                kind: .sleep,
                source: .fitbit,
                externalID: externalID,
                timestamp: start,
                value: Double(entry.minutesAsleep),
                unit: "min",
                text: "Sleep \(entry.minutesAsleep / 60)h \(entry.minutesAsleep % 60)m"
            )
        }
    }

    // MARK: - Biometrics ingestion

    private func ingestDailyBiometrics(
        date: Date,
        hrv: FitbitDTO.HRVResponse,
        hr: FitbitDTO.HeartRateResponse,
        spO2: FitbitDTO.SpO2Response,
        br: FitbitDTO.BreathingRateResponse,
        skin: FitbitDTO.SkinTempResponse
    ) throws {
        // Fitbit's daily summaries are single-row-per-day. We collapse them into one
        // BiometricSnapshot anchored at 06:00 local — a synthetic morning reading.
        let anchorTime = Calendar.current.date(
            bySettingHour: 6, minute: 0, second: 0, of: date
        ) ?? date

        let dailyHRV = hrv.hrv.first?.value.dailyRmssd
        let restingHR = hr.activitiesHeart.first?.value.restingHeartRate
        let spO2Avg = spO2.value?.avg
        let brAvg = br.br.first?.value.breathingRate
        let skinDelta = skin.tempSkin?.first?.value.nightlyRelative

        // Skip the row entirely if Fitbit gave us nothing — keeps the DB tidy.
        guard dailyHRV != nil || restingHR != nil || spO2Avg != nil
                || brAvg != nil || skinDelta != nil else { return }

        let externalID = "fitbit-daily-\(FitbitAPIClient.iso(date))"
        let descriptor = FetchDescriptor<BiometricSnapshot>(
            predicate: #Predicate { $0.sourceExternalID == externalID }
        )
        let existing = try modelContext.fetch(descriptor).first

        let snapshot = existing ?? BiometricSnapshot(
            timestamp: anchorTime,
            source: .fitbit,
            sourceExternalID: externalID
        )
        snapshot.timestamp = anchorTime
        snapshot.logicalDate = Calendar.current.startOfDay(for: date)
        snapshot.restingHeartRate = restingHR.map(Double.init)
        snapshot.hrv = dailyHRV
        snapshot.hrvKind = dailyHRV != nil ? BiometricSnapshot.HRVKind.rmssd.rawValue : nil
        snapshot.spO2 = spO2Avg
        snapshot.breathingRate = brAvg
        snapshot.skinTemperatureDelta = skinDelta

        if existing == nil {
            modelContext.insert(snapshot)
        }
    }

    // MARK: - Timeline anchors

    private func upsertContextAnchor(
        kind: ContextEvent.Kind,
        source: ContextEvent.Source,
        externalID: String,
        timestamp: Date,
        value: Double?,
        unit: String?,
        text: String?
    ) throws {
        let descriptor = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.sourceExternalID == externalID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.timestamp = timestamp
            existing.value = value
            existing.unit = unit
            existing.text = text
            existing.updatedAt = Date()
            return
        }
        let event = ContextEvent(
            timestamp: timestamp,
            kind: kind,
            value: value,
            unit: unit,
            text: text,
            source: source,
            sourceExternalID: externalID
        )
        modelContext.insert(event)
    }
}

// MARK: - Small util

extension FitbitAPIClient {
    /// Public ISO date formatter for callers that need to construct external IDs.
    static func iso(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}
