//
//  BaselineEngine.swift
//  Dialed
//
//  Computes rolling personal baselines from SleepSession + BiometricSnapshot
//  history. The pure math lives as static helpers (unit-tested) and the
//  orchestration method writes a PersonalBaseline row to SwiftData.
//

import Foundation
import SwiftData

enum BaselineEngine {

    // MARK: - Pure math

    /// Simple arithmetic mean. Nil for empty input.
    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (n-1 denominator). Nil for fewer than 2 values
    /// since a single sample has no spread.
    static func stdDev(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    /// Median. Nil for empty input. For even counts, average of the middle two.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// Median seconds-from-midnight for a list of dates, treating "before noon"
    /// values as the next day so a bedtime around midnight averages correctly.
    /// Result is normalized back to 0..<86400.
    ///
    /// Use this for **bedtimes**, where 23:50 one night and 00:10 the next
    /// should average to 00:00, not 12:00.
    static func medianBedtimeSeconds(from dates: [Date], calendar: Calendar = .current) -> Int? {
        guard !dates.isEmpty else { return nil }
        let shifted: [Double] = dates.map { date -> Double in
            let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
            let hour = comps.hour ?? 0
            let minute = comps.minute ?? 0
            let second = comps.second ?? 0
            var seconds = Double(hour * 3600 + minute * 60 + second)
            // Anything before noon is treated as belonging to the prior evening.
            if seconds < 12 * 3600 { seconds += 24 * 3600 }
            return seconds
        }
        guard let m = median(shifted) else { return nil }
        return Int(m.truncatingRemainder(dividingBy: 86400))
    }

    /// Median seconds-from-midnight for wake times — no wrap handling because
    /// people don't generally wake between noon and midnight.
    static func medianWakeTimeSeconds(from dates: [Date], calendar: Calendar = .current) -> Int? {
        guard !dates.isEmpty else { return nil }
        let secs: [Double] = dates.map { date -> Double in
            let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
            let hour = comps.hour ?? 0
            let minute = comps.minute ?? 0
            let second = comps.second ?? 0
            return Double(hour * 3600 + minute * 60 + second)
        }
        return median(secs).map { Int($0) }
    }

    // MARK: - Aggregate computation

    /// Compute a PersonalBaseline value object from arrays of source data.
    /// Returns the value object so callers can decide whether to persist it.
    struct Computed {
        var restingHRMean: Double?
        var restingHRStdDev: Double?
        var hrvMean: Double?
        var hrvStdDev: Double?
        var hrvKind: BiometricSnapshot.HRVKind?
        var sleepDurationMean: Double?
        var sleepDurationStdDev: Double?
        var deepMean: Double?
        var remMean: Double?
        var efficiencyMean: Double?
        var bedtimeSeconds: Int?
        var wakeTimeSeconds: Int?
        var spO2Mean: Double?
        var breathingRateMean: Double?
        var sampleDays: Int
    }

    /// Pure computation over already-filtered samples. Splitting this from the
    /// SwiftData fetch makes the math trivially unit-testable.
    static func compute(
        sleepSessions: [SleepSession],
        biometrics: [BiometricSnapshot]
    ) -> Computed {
        // Use main sleep only — Fitbit reports naps as separate sessions with
        // isMainSleep=false, which we filter out at ingestion. Defensive double-check
        // here would just look at logicalDate uniqueness; we accept what we're given.

        let sleepDurations = sleepSessions.map { Double($0.asleepMinutes) }
        let deepDurations = sleepSessions.compactMap { $0.deepMinutes.map(Double.init) }
        let remDurations = sleepSessions.compactMap { $0.remMinutes.map(Double.init) }
        let efficiencies = sleepSessions.compactMap { $0.efficiency }

        let restingHRs = biometrics.compactMap { $0.restingHeartRate }
        let hrvs = biometrics.compactMap { $0.hrv }
        let spO2s = biometrics.compactMap { $0.spO2 }
        let brs = biometrics.compactMap { $0.breathingRate }

        // Default to the dominant HRV kind among observations.
        let kindCounts = biometrics.compactMap { $0.hrvKind }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let dominantKey: String? = kindCounts.max(by: { $0.value < $1.value })?.key
        let dominantKind = dominantKey.flatMap(BiometricSnapshot.HRVKind.init(rawValue:))

        return Computed(
            restingHRMean: mean(restingHRs),
            restingHRStdDev: stdDev(restingHRs),
            hrvMean: mean(hrvs),
            hrvStdDev: stdDev(hrvs),
            hrvKind: dominantKind,
            sleepDurationMean: mean(sleepDurations),
            sleepDurationStdDev: stdDev(sleepDurations),
            deepMean: mean(deepDurations),
            remMean: mean(remDurations),
            efficiencyMean: mean(efficiencies),
            bedtimeSeconds: medianBedtimeSeconds(from: sleepSessions.map { $0.startTime }),
            wakeTimeSeconds: medianWakeTimeSeconds(from: sleepSessions.map { $0.endTime }),
            spO2Mean: mean(spO2s),
            breathingRateMean: mean(brs),
            sampleDays: max(sleepSessions.count, biometrics.count)
        )
    }

    // MARK: - SwiftData orchestration

    /// Recompute (or create) the PersonalBaseline row for `targetDate` using the
    /// trailing `windowDays` of data. Idempotent — calling twice updates in place.
    @MainActor
    static func recomputeBaseline(
        for targetDate: Date = Date(),
        windowDays: Int = 28,
        context: ModelContext
    ) throws -> PersonalBaseline {
        let calendar = Calendar.current
        let endOfDay = calendar.startOfDay(for: targetDate).addingTimeInterval(86_400)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: endOfDay) else {
            throw BaselineError.invalidWindow
        }

        let sleepDescriptor = FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.logicalDate >= windowStart && $0.logicalDate < endOfDay },
            sortBy: [SortDescriptor(\.logicalDate)]
        )
        let bioDescriptor = FetchDescriptor<BiometricSnapshot>(
            predicate: #Predicate { $0.logicalDate >= windowStart && $0.logicalDate < endOfDay },
            sortBy: [SortDescriptor(\.timestamp)]
        )

        let sessions = try context.fetch(sleepDescriptor)
        let bios = try context.fetch(bioDescriptor)

        let computed = compute(sleepSessions: sessions, biometrics: bios)

        // Upsert: one baseline row per (date, windowDays).
        let dayStart = calendar.startOfDay(for: targetDate)
        let existingDescriptor = FetchDescriptor<PersonalBaseline>(
            predicate: #Predicate {
                $0.date == dayStart && $0.windowDays == windowDays
            }
        )
        let baseline = try context.fetch(existingDescriptor).first
            ?? PersonalBaseline(date: dayStart, windowDays: windowDays)

        baseline.restingHeartRateMean = computed.restingHRMean
        baseline.restingHeartRateStdDev = computed.restingHRStdDev
        baseline.hrvMean = computed.hrvMean
        baseline.hrvStdDev = computed.hrvStdDev
        baseline.hrvKind = computed.hrvKind?.rawValue
        baseline.sleepDurationMinutesMean = computed.sleepDurationMean
        baseline.sleepDurationMinutesStdDev = computed.sleepDurationStdDev
        baseline.deepMinutesMean = computed.deepMean
        baseline.remMinutesMean = computed.remMean
        baseline.sleepEfficiencyMean = computed.efficiencyMean
        baseline.bedtimeMedianSecondsFromMidnight = computed.bedtimeSeconds
        baseline.wakeTimeMedianSecondsFromMidnight = computed.wakeTimeSeconds
        baseline.spO2Mean = computed.spO2Mean
        baseline.breathingRateMean = computed.breathingRateMean
        baseline.sampleDays = computed.sampleDays
        baseline.computedAt = Date()

        if baseline.modelContext == nil {
            context.insert(baseline)
        }

        return baseline
    }

    enum BaselineError: Error {
        case invalidWindow
    }
}
