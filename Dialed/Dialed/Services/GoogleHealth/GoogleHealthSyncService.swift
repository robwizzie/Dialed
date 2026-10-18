//
//  GoogleHealthSyncService.swift
//  Dialed
//
//  Pixel Watch → Google Health API → SwiftData. Nightly sleep sessions
//  become SleepSession rows and daily vitals (resting HR, HRV, SpO₂,
//  breathing) become one BiometricSnapshot per day, so the rest of the
//  app (StateEngine, Home, Trends) works unchanged. Idempotent: re-syncing
//  a day updates rather than duplicates.
//
//  Live values (current heart rate, steps, water, weigh-ins) are read
//  directly by `fetchLive` and not stored.
//

import Foundation
import SwiftData

@MainActor
final class GoogleHealthSyncService {
    private let api = GoogleHealthAPI.shared
    private let context: ModelContext

    private(set) var lastError: String?

    struct Live {
        var heartRate: (date: Date, bpm: Double)?
        var stepsByDay: [Date: Double] = [:]
        var waterOzToday: Double?
    }

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    static var isConnected: Bool { GoogleHealthTokenStore.isConnected }

    // MARK: - Stored sync (sleep + daily vitals)

    func sync(days: Int) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let since = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return }
        let sinceDay = GHDate(since).iso
        lastError = nil

        // Each type is independent — one failing (e.g. no SpO₂ yet) shouldn't
        // block the others.
        do {
            let sleeps = try await api.list("sleep", filter: "sleep.interval.end_time >= \"\(GHTime.rfc3339(since))\"")
            try ingestSleep(sleeps)
        } catch { record(error) }

        var vitals: [Date: (rhr: Double?, hrv: Double?, spo2: Double?, br: Double?)] = [:]
        func put(_ date: GHDate?, _ update: (inout (rhr: Double?, hrv: Double?, spo2: Double?, br: Double?)) -> Void) {
            guard let day = date?.date(calendar: calendar) else { return }
            var row = vitals[day] ?? (nil, nil, nil, nil)
            update(&row)
            vitals[day] = row
        }

        do {
            for p in try await api.list("daily-resting-heart-rate", filter: "daily_resting_heart_rate.date >= \"\(sinceDay)\"") {
                guard let v = p.dailyRestingHeartRate else { continue }
                put(v.date) { $0.rhr = v.beatsPerMinute.map { Double($0.value) } }
            }
        } catch { record(error) }
        do {
            for p in try await api.list("daily-heart-rate-variability", filter: "daily_heart_rate_variability.date >= \"\(sinceDay)\"") {
                guard let v = p.dailyHeartRateVariability else { continue }
                put(v.date) { $0.hrv = v.averageHeartRateVariabilityMilliseconds }
            }
        } catch { record(error) }
        do {
            for p in try await api.list("daily-oxygen-saturation", filter: "daily_oxygen_saturation.date >= \"\(sinceDay)\"") {
                guard let v = p.dailyOxygenSaturation else { continue }
                put(v.date) { $0.spo2 = v.averagePercentage }
            }
        } catch { record(error) }
        do {
            for p in try await api.list("daily-respiratory-rate", filter: "daily_respiratory_rate.date >= \"\(sinceDay)\"") {
                guard let v = p.dailyRespiratoryRate else { continue }
                put(v.date) { $0.br = v.breathsPerMinute }
            }
        } catch { record(error) }

        for (day, row) in vitals {
            upsertDailySnapshot(day: day, rhr: row.rhr, hrv: row.hrv, spo2: row.spo2, breathing: row.br)
        }
        try? context.save()
    }

    // MARK: - Live reads

    func fetchLive() async -> Live {
        var live = Live()
        let calendar = Calendar.current
        let now = Date()

        if let points = try? await api.list(
            "heart-rate",
            filter: "heart_rate.sample_time.physical_time >= \"\(GHTime.rfc3339(now.addingTimeInterval(-45 * 60)))\""
        ) {
            let samples = points.compactMap { p -> (Date, Double)? in
                guard let hr = p.heartRate, let bpm = hr.beatsPerMinute?.value,
                      let t = GHTime.parse(hr.sampleTime?.physicalTime) else { return nil }
                return (t, Double(bpm))
            }
            if let latest = samples.max(by: { $0.0 < $1.0 }) {
                live.heartRate = (latest.0, latest.1)
            }
        }

        if let points = try? await api.dailyRollUp("steps", days: 7) {
            for p in points {
                guard let day = p.civilStartTime?.date.date(calendar: calendar),
                      let count = p.steps?.countSum?.value else { continue }
                live.stepsByDay[calendar.startOfDay(for: day)] = Double(count)
            }
        }

        if let points = try? await api.dailyRollUp("hydration-log", days: 1),
           let ml = points.last?.hydrationLog?.amountConsumed?.millilitersSum {
            live.waterOzToday = ml / 29.5735
        }
        return live
    }

    /// Weigh-ins (from any scale synced to the Google account), in lbs.
    func weights(since start: Date) async -> [WeightReading] {
        guard let points = try? await api.list(
            "weight",
            filter: "weight.sample_time.physical_time >= \"\(GHTime.rfc3339(start))\""
        ) else { return [] }
        return points.compactMap { p in
            guard let w = p.weight, let grams = w.weightGrams,
                  let t = GHTime.parse(w.sampleTime?.physicalTime) else { return nil }
            return WeightReading(date: t, pounds: grams / 453.59237, source: .googleHealth)
        }
    }

    // MARK: - Ingestion

    private func ingestSleep(_ points: [GHDataPoint]) throws {
        for point in points {
            guard let sleep = point.sleep,
                  sleep.metadata?.nap != true,
                  let start = GHTime.parse(sleep.interval?.startTime),
                  let end = GHTime.parse(sleep.interval?.endTime) else { continue }
            let asleep = sleep.summary?.minutesAsleep?.value ?? Int(end.timeIntervalSince(start) / 60)
            let inBed = sleep.summary?.minutesInSleepPeriod?.value ?? Int(end.timeIntervalSince(start) / 60)
            let externalID = "ghealth-sleep-" + (point.name ?? sleep.metadata?.externalId ?? String(Int(start.timeIntervalSince1970)))

            let descriptor = FetchDescriptor<SleepSession>(predicate: #Predicate { $0.sourceExternalID == externalID })
            let existing = try context.fetch(descriptor).first
            let session = existing ?? SleepSession(
                startTime: start, endTime: end,
                inBedMinutes: inBed, asleepMinutes: asleep,
                source: .googleHealth, sourceExternalID: externalID
            )
            session.startTime = start
            session.endTime = end
            session.logicalDate = Calendar.current.startOfDay(for: end)
            session.inBedMinutes = inBed
            session.asleepMinutes = asleep
            session.efficiency = inBed > 0 ? Double(asleep) / Double(inBed) : nil
            session.deepMinutes = sleep.minutes(of: "DEEP")
            session.remMinutes = sleep.minutes(of: "REM")
            session.lightMinutes = sleep.minutes(of: "LIGHT")
            session.awakeMinutes = sleep.minutes(of: "AWAKE") ?? sleep.summary?.minutesAwake?.value
            if existing == nil {
                context.insert(session)
            } else {
                session.updatedAt = Date()
            }
        }
    }

    private func upsertDailySnapshot(day: Date, rhr: Double?, hrv: Double?, spo2: Double?, breathing: Double?) {
        let externalID = "ghealth-daily-\(GHDate(day).iso)"
        let descriptor = FetchDescriptor<BiometricSnapshot>(predicate: #Predicate { $0.sourceExternalID == externalID })
        let existing = (try? context.fetch(descriptor))?.first
        let anchor = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: day) ?? day
        let snapshot = existing ?? BiometricSnapshot(timestamp: anchor, source: .googleHealth, sourceExternalID: externalID)
        snapshot.timestamp = anchor
        snapshot.logicalDate = Calendar.current.startOfDay(for: day)
        if let rhr { snapshot.restingHeartRate = rhr }
        if let hrv {
            snapshot.hrv = hrv
            snapshot.hrvKind = BiometricSnapshot.HRVKind.rmssd.rawValue
        }
        if let spo2 { snapshot.spO2 = spo2 }
        if let breathing { snapshot.breathingRate = breathing }
        if existing == nil { context.insert(snapshot) }
    }

    private func record(_ error: Error) {
        if lastError == nil { lastError = error.localizedDescription }
    }
}
