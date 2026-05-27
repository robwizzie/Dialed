//
//  InsightEngine.swift
//  Dialed
//
//  Rules-based nightly pass that annotates ContextEvents with a short
//  human-readable reason whenever a behavior on day X coincides with a
//  measurable sleep regression on the night that followed. Not an LLM —
//  these are deliberate pattern matchers so the annotations stay
//  predictable and testable. The Timeline renders aiAnnotation under
//  every event automatically.
//
//  Timing convention:
//    - day X is the logicalDate of the events being analyzed.
//    - "next night's sleep" is the SleepSession with logicalDate = X + 1
//      (it started the evening of X and ended the morning of X + 1).
//    - This pass runs from PlanGenerator on day X + 1, by which point
//      the relevant sleep has been ingested.
//
//  Idempotency:
//    - We OWN ContextEvent.aiAnnotation for now. Each pass clears all
//      annotations on the day's events first, then re-applies — so
//      rules can be tweaked and stale annotations disappear cleanly.
//

import Foundation
import SwiftData

@MainActor
enum InsightEngine {

    /// Run every rule against day `day` and write resulting annotations
    /// onto the matching ContextEvents.
    static func runDailyPass(for day: Date, context: ModelContext) {
        let cal = Calendar.current
        let logicalDay = cal.startOfDay(for: day)

        let events = dayEvents(for: logicalDay, context: context)
        let nextNightSleep = nextNightSleep(after: logicalDay, context: context)
        let baseline = (try? context.fetch(FetchDescriptor<PersonalBaseline>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )))?.first

        // Capture which events had an annotation BEFORE we clear, so we
        // know whether the clear itself produced a meaningful change. The
        // engine is currently the only writer of aiAnnotation, so any
        // pre-existing annotation came from a prior pass — clearing it
        // when no rule rewrites it is the "stale annotation cleanup"
        // behavior we promise.
        let hadAnnotation = events.contains { $0.aiAnnotation != nil }
        for event in events { event.aiAnnotation = nil }

        let rules: [InsightRule] = [
            LateCaffeineRule(),
            LateMealRule(),
            AlcoholRule()
        ]

        var written = 0
        for rule in rules {
            let outputs = rule.apply(
                events: events,
                nextNightSleep: nextNightSleep,
                baseline: baseline
            )
            for (event, annotation) in outputs {
                event.aiAnnotation = annotation
                written += 1
            }
        }

        // Save when we wrote something OR when we cleared a stale set
        // (otherwise the cleared-to-nil state lives only in memory).
        if written > 0 || hadAnnotation {
            try? context.save()
        }
    }

    // MARK: - Fetch helpers

    private static func dayEvents(for day: Date, context: ModelContext) -> [ContextEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let desc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate {
                $0.logicalDate >= start && $0.logicalDate < end
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    private static func nextNightSleep(after day: Date, context: ModelContext) -> SleepSession? {
        let cal = Calendar.current
        guard let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) else { return nil }
        let nextDayEnd = cal.date(byAdding: .day, value: 1, to: nextDay) ?? nextDay
        let desc = FetchDescriptor<SleepSession>(
            predicate: #Predicate {
                $0.logicalDate >= nextDay && $0.logicalDate < nextDayEnd
            },
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        return (try? context.fetch(desc))?.first
    }
}

// MARK: - Rule contract

/// Pure: takes a day's evidence, returns a list of annotations to apply.
/// Implementations must not mutate inputs.
protocol InsightRule {
    func apply(
        events: [ContextEvent],
        nextNightSleep: SleepSession?,
        baseline: PersonalBaseline?
    ) -> [(event: ContextEvent, annotation: String)]
}

// MARK: - LateCaffeineRule

/// Caffeine logged after 14:00 + the next night's sleep efficiency dropped
/// below baseline → annotate the caffeine event.
struct LateCaffeineRule: InsightRule {
    /// Threshold hour — caffeine logged at or after this hour is considered
    /// "late" for the purpose of this rule.
    let lateHour: Int
    /// Minimum efficiency drop (percentage points) before we annotate, so
    /// noise day-to-day doesn't trip us.
    let minEfficiencyDropPercentPoints: Double

    init(lateHour: Int = 14, minEfficiencyDropPercentPoints: Double = 4) {
        self.lateHour = lateHour
        self.minEfficiencyDropPercentPoints = minEfficiencyDropPercentPoints
    }

    func apply(
        events: [ContextEvent],
        nextNightSleep: SleepSession?,
        baseline: PersonalBaseline?
    ) -> [(event: ContextEvent, annotation: String)] {
        guard let sleep = nextNightSleep,
              let efficiency = sleep.efficiency,
              let baselineEff = baseline?.sleepEfficiencyMean else { return [] }
        let dropPP = (baselineEff - efficiency) * 100
        guard dropPP >= minEfficiencyDropPercentPoints else { return [] }

        let cal = Calendar.current
        let lateCaffeine = events.filter {
            $0.kind == .caffeine
            && cal.component(.hour, from: $0.timestamp) >= lateHour
        }
        guard let latest = lateCaffeine.last else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeStr = formatter.string(from: latest.timestamp)
        let dropStr = String(format: "%.0f", dropPP)
        return [(latest, "Sleep efficiency dropped \(dropStr) pts — late caffeine at \(timeStr) may have stretched onset.")]
    }
}

// MARK: - LateMealRule

/// Large meal (>= minCalories) within `windowHours` of sleep start + REM
/// dropped vs baseline → annotate the meal.
struct LateMealRule: InsightRule {
    let minCalories: Double
    let windowHours: Double
    let minREMDropMinutes: Double

    init(minCalories: Double = 500, windowHours: Double = 3, minREMDropMinutes: Double = 20) {
        self.minCalories = minCalories
        self.windowHours = windowHours
        self.minREMDropMinutes = minREMDropMinutes
    }

    func apply(
        events: [ContextEvent],
        nextNightSleep: SleepSession?,
        baseline: PersonalBaseline?
    ) -> [(event: ContextEvent, annotation: String)] {
        guard let sleep = nextNightSleep,
              let remMinutes = sleep.remMinutes.map(Double.init),
              let baselineREM = baseline?.remMinutesMean else { return [] }
        let dropMinutes = baselineREM - remMinutes
        guard dropMinutes >= minREMDropMinutes else { return [] }

        let cutoff = sleep.startTime.addingTimeInterval(-windowHours * 3600)
        let lateMeals = events.filter { event in
            guard event.kind == .meal,
                  let calories = event.value, calories >= minCalories else { return false }
            return event.timestamp >= cutoff && event.timestamp < sleep.startTime
        }
        guard let target = lateMeals.last else { return [] }

        let dropStr = Int(dropMinutes.rounded())
        return [(target, "REM dropped \(dropStr) min — large meal close to bed left digestion competing with sleep.")]
    }
}

// MARK: - AlcoholRule

/// Any alcohol logged + next night's deep sleep dropped > minDropPP of
/// baseline → annotate the alcohol event. Alcohol's deep-sleep suppression
/// is well-documented, so we don't need a big drop to surface it.
struct AlcoholRule: InsightRule {
    /// Percentage drop in deep-sleep minutes vs. baseline before we
    /// annotate (15% by default — beyond noise).
    let minDeepDropPercent: Double

    init(minDeepDropPercent: Double = 15) {
        self.minDeepDropPercent = minDeepDropPercent
    }

    func apply(
        events: [ContextEvent],
        nextNightSleep: SleepSession?,
        baseline: PersonalBaseline?
    ) -> [(event: ContextEvent, annotation: String)] {
        guard let sleep = nextNightSleep,
              let deepMinutes = sleep.deepMinutes.map(Double.init),
              let baselineDeep = baseline?.deepMinutesMean,
              baselineDeep > 0 else { return [] }
        let dropPercent = (baselineDeep - deepMinutes) / baselineDeep * 100
        guard dropPercent >= minDeepDropPercent else { return [] }

        let alcoholEvents = events.filter { $0.kind == .alcohol }
        guard let target = alcoholEvents.last else { return [] }

        let pctStr = Int(dropPercent.rounded())
        return [(target, "Deep sleep dropped \(pctStr)% — alcohol typically suppresses it for 4–6 hours.")]
    }
}
