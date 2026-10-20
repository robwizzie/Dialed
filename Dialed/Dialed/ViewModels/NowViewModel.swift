//
//  NowViewModel.swift
//  Dialed
//
//  Drives the Home state strip: reads PersonalBaseline + latest
//  SleepSession + latest BiometricSnapshot + today's ContextEvents and runs
//  them through StateEngine for Recovery, Readiness, Energy and Strain.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class NowViewModel: ObservableObject {

    // MARK: - Published state

    @Published var recovery: StateEngine.ScoreBreakdown = .empty
    @Published var readiness: StateEngine.ScoreBreakdown = .empty
    @Published var energy: StateEngine.ScoreBreakdown = .empty
    @Published var strain: StateEngine.ScoreBreakdown = .empty

    // MARK: - Refresh

    func refresh(context: ModelContext) async {
        let now = Date()

        // 1. Load the baseline, latest sleep, latest biometric. Refresh the
        //    baseline first — no-op unless it's a new logical day or new
        //    sleep/biometric rows have synced since the last compute.
        BaselineEngine.recomputeIfNeeded(now: now, context: context)
        let baseline = latestBaseline(context: context)
        let lastSleep = latestSleep(context: context)
        let latestBio = latestBiometric(context: context)

        // 2. Today's load — pull from legacy DayLog so we don't depend on
        //    Phase 3 plumbing yet.
        let dayLog = todayLog(context: context)
        let dayLoad = StateEngine.DayLoadInputs(
            steps: dayLog?.steps ?? 0,
            activeCalories: dayLog?.activeEnergyBurned ?? 0,
            exerciseMinutes: dayLog?.exerciseMinutes ?? 0,
            workoutDurationMinutes: dayLog?.workoutDurationMinutes ?? 0,
            workoutIntensity: nil
        )

        // 3. Energy context — pull caffeine / meal / workout timing from
        //    today's ContextEvents.
        let energyCtx = buildEnergyContext(context: context, now: now)

        // 4. Run the engine.
        let inputs = StateEngine.LiveInputs(
            now: now,
            baseline: StateEngine.BaselineInputs.from(baseline),
            lastSleep: StateEngine.SleepInputs.from(lastSleep),
            latestBiometric: StateEngine.BiometricInputs.from(latestBio),
            dayLoad: dayLoad,
            energyContext: energyCtx
        )

        let recoveryResult = StateEngine.recovery(inputs)
        let strainResult = StateEngine.strain(inputs)
        let readinessResult = StateEngine.readiness(
            inputs,
            recoveryScore: recoveryResult.score,
            weeklyAdherence: weeklyAdherence(context: context),
            recentStrain: strainResult.score
        )
        let energyResult = StateEngine.energy(inputs, recoveryScore: recoveryResult.score)

        self.recovery = recoveryResult
        self.readiness = readinessResult
        self.energy = energyResult
        self.strain = strainResult

        // Persist today's snapshot so Trends loads instantly and tomorrow's
        // recentStrain calc has something to read. force:false skips the
        // write if a fresh row exists (computed in the last minute) — guards
        // against the rapid-fire refreshes that happen when the user pulls
        // to refresh repeatedly.
        // Pass the logical day so the snapshot lands on the right row when
        // we're between midnight and the 4 AM cutoff.
        DailyScoreSnapshotter.snapshot(
            for: Calendar.current.logicalStartOfDay(for: now),
            context: context,
            force: false
        )
    }

    // MARK: - Data fetchers

    private func latestBaseline(context: ModelContext) -> PersonalBaseline? {
        var desc = FetchDescriptor<PersonalBaseline>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first
    }

    private func latestSleep(context: ModelContext) -> SleepSession? {
        var desc = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first
    }

    private func latestBiometric(context: ModelContext) -> BiometricSnapshot? {
        var desc = FetchDescriptor<BiometricSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first
    }

    private func todayLog(context: ModelContext) -> DayLog? {
        let today = Calendar.current.startOfDay(for: Date())
        let desc = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date == today }
        )
        return (try? context.fetch(desc))?.first
    }

    private func buildEnergyContext(context: ModelContext, now: Date) -> StateEngine.EnergyContext {
        // logicalStartOfDay applies the 4 AM cutoff, matching how
        // ContextEvent.logicalDate is stored. Without this, queries between
        // midnight and 4 AM miss events the user just logged.
        let today = Calendar.current.logicalStartOfDay(for: now)
        let desc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate == today },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let events = (try? context.fetch(desc)) ?? []

        let lastCaffeine = events.first { $0.kindRaw == ContextEvent.Kind.caffeine.rawValue }
        let lastMeal = events.first { $0.kindRaw == ContextEvent.Kind.meal.rawValue }
        let lastWorkout = events.first { $0.kindRaw == ContextEvent.Kind.workout.rawValue }
        let lastEnergyRating = events.first { $0.kindRaw == ContextEvent.Kind.energy.rawValue }

        let minutesSince: (Date) -> Int = { Int(now.timeIntervalSince($0) / 60) }

        var activeMG: Double? = nil
        if let caf = lastCaffeine, let mg = caf.value {
            activeMG = StateEngine.activeCaffeine(doseMG: mg, dosedAt: caf.timestamp, now: now)
        }

        // Anchor "minutes since workout" to when the workout ENDED, not
        // when it was logged. Workout events store duration in `value`
        // (minutes), so the actual end is timestamp + value.
        let workoutEnd: Date? = lastWorkout.map { event in
            let durationMin = event.value ?? 0
            return event.timestamp.addingTimeInterval(durationMin * 60)
        }

        return StateEngine.EnergyContext(
            minutesSinceCaffeine: lastCaffeine.map { minutesSince($0.timestamp) },
            activeCaffeineMG: activeMG,
            minutesSinceMeal: lastMeal.map { minutesSince($0.timestamp) },
            minutesSinceWorkout: workoutEnd.map { minutesSince($0) },
            selfReported: clampedSelfEnergy(from: lastEnergyRating)
        )
    }

    /// Voice + manual paths clamp 1–5, but a migrated or buggy event
    /// could have a `value` outside that range or NaN/Infinity. Guard
    /// against the `Int(NaN)` trap.
    private func clampedSelfEnergy(from event: ContextEvent?) -> Int? {
        guard let value = event?.value, value.isFinite else { return nil }
        return max(1, min(5, Int(value.rounded())))
    }

    private func weeklyAdherence(context: ModelContext) -> Double {
        // Read from the real plan via AdherenceTracker. Falls back to the
        // legacy DayLog checklist for users whose history predates Phase 3
        // (no PlanBlocks yet) so we don't crater their Readiness on day 1.
        if let planAdherence = AdherenceTracker.weeklyAdherence(context: context) {
            return planAdherence
        }
        // Legacy fallback
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return 0.7 }
        let desc = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date >= weekAgo },
            sortBy: [SortDescriptor(\.date)]
        )
        let logs = (try? context.fetch(desc)) ?? []
        guard !logs.isEmpty else { return 0.7 }
        let totals = logs.reduce(into: (done: 0, total: 0)) { acc, log in
            for item in (log.checklistItems ?? []) {
                acc.total += 1
                if item.checklistStatus == .done { acc.done += 1 }
            }
        }
        guard totals.total > 0 else { return 0.7 }
        return Double(totals.done) / Double(totals.total)
    }
}

// MARK: - Empty breakdown for first paint

extension StateEngine.ScoreBreakdown {
    static let empty = StateEngine.ScoreBreakdown(
        score: 0,
        grade: .poor,
        contributions: [],
        confidence: 0
    )
}
