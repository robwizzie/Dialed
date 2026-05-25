//
//  AdherenceTracker.swift
//  Dialed
//
//  Computes how well the user has stuck to their plan over the trailing
//  N days. Plugs into DailyScoreSnapshotter to replace the 1.0 placeholder
//  that Readiness was using.
//
//  The math:
//    adherence = done / (done + skipped + ignored)
//  where `ignored` is a past block (startTime < now) that's still
//  .upcoming — i.e., the user never even pressed "skip", they just let
//  it pass. Ignoring a block is a stronger negative signal than
//  consciously skipping it, but we lump them together for this score.
//
//  Returns nil when there are no scoreable blocks in the window so
//  callers can decide on a default rather than picking up a misleading
//  zero.
//

import Foundation
import SwiftData

@MainActor
enum AdherenceTracker {

    /// 0–1 fraction of the trailing `days` days of plan blocks the user
    /// actually completed. nil when there's nothing to measure (no plans,
    /// or every block is still in the future).
    static func weeklyAdherence(
        ending endDay: Date = Date(),
        days: Int = 7,
        context: ModelContext
    ) -> Double? {
        let summary = summary(ending: endDay, days: days, context: context)
        return summary.adherence
    }

    /// Same as weeklyAdherence but returns the underlying counts too —
    /// useful for "you hit 12 of 15 blocks this week" copy in the UI.
    static func summary(
        ending endDay: Date = Date(),
        days: Int = 7,
        context: ModelContext,
        now: Date = Date()
    ) -> Summary {
        let cal = Calendar.current
        let end = cal.startOfDay(for: endDay)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: end) else {
            return Summary(done: 0, skipped: 0, ignored: 0, pending: 0)
        }
        let nextDayAfterEnd = cal.date(byAdding: .day, value: 1, to: end) ?? end

        let plansDesc = FetchDescriptor<DailyPlan>(
            predicate: #Predicate {
                $0.date >= start && $0.date < nextDayAfterEnd
            }
        )
        let plans = (try? context.fetch(plansDesc)) ?? []
        let blocks = plans.flatMap { $0.blocks ?? [] }
            .filter { isScoreable($0) }

        var done = 0
        var skipped = 0
        var ignored = 0
        var pending = 0

        for block in blocks {
            switch block.status {
            case .done:
                done += 1
            case .skipped:
                skipped += 1
            case .upcoming, .active, .due:
                // If the block's window has passed but it's still upcoming,
                // treat it as ignored. Otherwise it's just pending.
                if block.startTime < now {
                    ignored += 1
                } else {
                    pending += 1
                }
            }
        }

        return Summary(done: done, skipped: skipped, ignored: ignored, pending: pending)
    }

    /// Some block kinds are status anchors rather than completable tasks.
    /// Excluding them keeps adherence honest — you don't "complete" the
    /// fact that you woke up.
    private static func isScoreable(_ block: PlanBlock) -> Bool {
        switch block.kind {
        case .wake, .sleep, .mood, .rest:
            return false
        case .skincare, .supplement, .hydration, .meal, .caffeine,
             .workout, .cardio, .deepWork, .windDown, .routine:
            return true
        }
    }

    // MARK: - Summary

    struct Summary: Equatable {
        let done: Int
        let skipped: Int
        let ignored: Int
        let pending: Int

        /// Total scoreable blocks whose outcome is known (past + decided).
        var scored: Int { done + skipped + ignored }

        /// 0–1 ratio; nil when nothing's been scored yet.
        var adherence: Double? {
            guard scored > 0 else { return nil }
            return Double(done) / Double(scored)
        }
    }
}
