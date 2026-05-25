//
//  DailyScoreSnapshotter.swift
//  Dialed
//
//  Computes and persists DailyScoreSnapshot rows. Keeps the score
//  calculation logic in one place so NowViewModel, PillarTrendsViewModel,
//  and any future background refresh can share it.
//
//  Snapshots are upserts keyed on logicalDate. Calling snapshot(for:)
//  twice for the same day overwrites the prior row in place.
//

import Foundation
import SwiftData

@MainActor
enum DailyScoreSnapshotter {

    /// Compute + persist a snapshot for a single day. Returns the
    /// resulting row. Pass `force: false` to skip work if the existing
    /// snapshot is fresh (computed in the last minute) — useful when
    /// NowViewModel triggers refresh on every screen appear.
    @discardableResult
    static func snapshot(
        for day: Date,
        context: ModelContext,
        force: Bool = true
    ) -> DailyScoreSnapshot {
        let logicalDay = Calendar.current.startOfDay(for: day)
        let existing = fetch(logicalDate: logicalDay, context: context)

        if let existing, !force,
           Date().timeIntervalSince(existing.computedAt) < 60 {
            return existing
        }

        let baseline = (try? context.fetch(FetchDescriptor<PersonalBaseline>()))?.first
        let baselineInputs = StateEngine.BaselineInputs.from(baseline)

        let sleep = latestSleep(for: logicalDay, context: context)
        let bio = latestBiometric(for: logicalDay, context: context)
        let load = dayLoad(for: logicalDay, context: context)
        let selfEnergy = averageSelfEnergy(for: logicalDay, context: context)

        // We use "21:00 on the snapshot date" as the synthetic "now" so
        // Energy's circadian curve evaluates against a stable end-of-day
        // anchor rather than wherever the user happens to open the app.
        let anchor = Calendar.current.date(byAdding: .hour, value: 21, to: logicalDay) ?? logicalDay

        let inputs = StateEngine.LiveInputs(
            now: anchor,
            baseline: baselineInputs,
            lastSleep: StateEngine.SleepInputs.from(sleep),
            latestBiometric: StateEngine.BiometricInputs.from(bio),
            dayLoad: load,
            energyContext: StateEngine.EnergyContext(selfReported: selfEnergy)
        )

        // Recovery requires sleep — without it we emit nil rather than
        // a fabricated score.
        let recovery = (sleep != nil) ? StateEngine.recovery(inputs) : nil
        let strain = StateEngine.strain(inputs)
        let adherence = AdherenceTracker.weeklyAdherence(
            ending: logicalDay, days: 7, context: context
        ) ?? 1.0
        let readiness = recovery.map {
            StateEngine.readiness(inputs, recoveryScore: $0.score,
                                  weeklyAdherence: adherence,
                                  recentStrain: priorDayStrain(before: logicalDay, context: context))
        }
        // Energy proxy: scale 1–5 self-reported avg to 0–100. Skip when
        // no mood/energy events were logged.
        let energyScore: Int? = selfEnergy.map { Int((Double($0) / 5.0 * 100).rounded()) }

        let row = existing ?? DailyScoreSnapshot(logicalDate: logicalDay)
        row.recoveryScore     = recovery?.score
        row.recoveryConfidence = recovery?.confidence
        row.readinessScore    = readiness?.score
        row.readinessConfidence = readiness?.confidence
        row.energyScore       = energyScore
        row.energyConfidence  = (energyScore != nil) ? 0.5 : nil
        row.strainScore       = strain.score
        row.strainConfidence  = strain.confidence
        row.computedAt        = Date()

        if existing == nil {
            context.insert(row)
        }
        try? context.save()
        return row
    }

    /// Backfill snapshots for the trailing `days` days. Safe to call on
    /// app launch — skips days that already have a snapshot.
    static func backfill(days: Int, context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            if fetch(logicalDate: day, context: context) == nil {
                snapshot(for: day, context: context)
            }
        }
    }

    /// Fetch all snapshots in [from, to] inclusive, ascending by date.
    static func fetch(
        from: Date,
        to: Date,
        context: ModelContext
    ) -> [DailyScoreSnapshot] {
        let cal = Calendar.current
        let lo = cal.startOfDay(for: from)
        let hi = cal.startOfDay(for: to)
        let desc = FetchDescriptor<DailyScoreSnapshot>(
            predicate: #Predicate {
                $0.logicalDate >= lo && $0.logicalDate <= hi
            },
            sortBy: [SortDescriptor(\.logicalDate, order: .forward)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    // MARK: - Internals

    static func fetch(logicalDate: Date, context: ModelContext) -> DailyScoreSnapshot? {
        let day = Calendar.current.startOfDay(for: logicalDate)
        let desc = FetchDescriptor<DailyScoreSnapshot>(
            predicate: #Predicate { $0.logicalDate == day }
        )
        return (try? context.fetch(desc))?.first
    }

    private static func priorDayStrain(before day: Date, context: ModelContext) -> Int {
        guard let prior = Calendar.current.date(byAdding: .day, value: -1, to: day),
              let snap = fetch(logicalDate: prior, context: context),
              let s = snap.strainScore else {
            return 0
        }
        return s
    }

    private static func latestSleep(for day: Date, context: ModelContext) -> SleepSession? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let desc = FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < end },
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        return (try? context.fetch(desc))?.first
    }

    private static func latestBiometric(for day: Date, context: ModelContext) -> BiometricSnapshot? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let desc = FetchDescriptor<BiometricSnapshot>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < end },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(desc))?.first
    }

    private static func dayLoad(for day: Date, context: ModelContext) -> StateEngine.DayLoadInputs {
        var load = StateEngine.DayLoadInputs()
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start

        if let bio = latestBiometric(for: day, context: context) {
            load.steps = bio.stepsSoFar ?? 0
        }
        let workoutDesc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate {
                $0.logicalDate >= start
                && $0.logicalDate < end
                && $0.kindRaw == "workout"
            }
        )
        for w in (try? context.fetch(workoutDesc)) ?? [] {
            load.workoutDurationMinutes += Int(w.value ?? 0)
            load.activeCalories += Int(w.secondaryValue ?? 0)
        }
        return load
    }

    private static func averageSelfEnergy(for day: Date, context: ModelContext) -> Int? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let desc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate {
                $0.logicalDate >= start
                && $0.logicalDate < end
                && ($0.kindRaw == "mood" || $0.kindRaw == "energy")
            }
        )
        let events = (try? context.fetch(desc)) ?? []
        let values = events.compactMap { $0.value }
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }
}
