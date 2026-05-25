//
//  PillarTrendsViewModel.swift
//  Dialed
//
//  Builds per-day score series for the four pillars over a chosen window.
//  Pulls historical SleepSession + BiometricSnapshot + ContextEvent +
//  DayLog rows out of SwiftData and reconstructs StateEngine scores for
//  each day, then surfaces the series + simple summary stats (avg, min,
//  max, trend) to the Trends view.
//
//  Limitations:
//    - StateEngine.energy is intentionally time-of-day sensitive (caffeine
//      decay, circadian curve, post-meal slump). Historical "energy" is
//      modeled here as the day's average self-reported energy/mood from
//      ContextEvent — a fair proxy without inventing fake circadian state.
//    - StateEngine.readiness needs weeklyAdherence + recentStrain. We
//      approximate adherence as a 1.0 placeholder until the adherence
//      tracker lands; recentStrain is the prior day's strain score.
//

import Foundation
import SwiftData

@MainActor
final class PillarTrendsViewModel: ObservableObject {

    enum Pillar: String, CaseIterable, Identifiable {
        case recovery, readiness, energy, strain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recovery:  return "Recovery"
            case .readiness: return "Readiness"
            case .energy:    return "Energy"
            case .strain:    return "Strain"
            }
        }
    }

    enum Window: String, CaseIterable, Identifiable {
        case week = "7D"
        case twoWeeks = "14D"
        case month = "30D"

        var id: String { rawValue }
        var days: Int {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 30
            }
        }
    }

    struct DailyPoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let score: Int?
    }

    struct Summary: Equatable {
        let average: Int?
        let min: Int?
        let max: Int?
        /// Slope in points/day across the window. Positive = improving for
        /// pillars where higher is better (recovery/readiness/energy);
        /// strain is just descriptive (higher = more loaded).
        let trendPerDay: Double?
    }

    @Published var window: Window = .week
    @Published var selectedPillar: Pillar = .recovery
    @Published private(set) var series: [Pillar: [DailyPoint]] = [:]

    // MARK: - Loading

    func load(context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<window.days).compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }.reversed().map { $0 }  // oldest → newest

        // Pull baseline once — used for every day's recovery calc.
        let baseline = (try? context.fetch(FetchDescriptor<PersonalBaseline>()))?.first
        let baselineInputs = StateEngine.BaselineInputs.from(baseline)

        var recovery: [DailyPoint] = []
        var readiness: [DailyPoint] = []
        var energy: [DailyPoint] = []
        var strain: [DailyPoint] = []

        var priorDayStrain = 0
        for day in days {
            let sleep = latestSleep(for: day, context: context)
            let biometric = latestBiometric(for: day, context: context)
            let load = dayLoad(for: day, context: context)
            let selfEnergy = averageSelfEnergy(for: day, context: context)

            let inputs = StateEngine.LiveInputs(
                now: cal.date(byAdding: .hour, value: 21, to: day) ?? day,  // pretend 9pm — score is "end-of-day" snapshot
                baseline: baselineInputs,
                lastSleep: StateEngine.SleepInputs.from(sleep),
                latestBiometric: StateEngine.BiometricInputs.from(biometric),
                dayLoad: load,
                energyContext: StateEngine.EnergyContext(selfReported: selfEnergy)
            )

            // Recovery needs sleep — without it the score is misleading,
            // so we emit nil for the day and let the chart break.
            let recBreakdown: StateEngine.ScoreBreakdown? = (sleep != nil)
                ? StateEngine.recovery(inputs) : nil
            let strainBreakdown = StateEngine.strain(inputs)

            recovery.append(.init(date: day, score: recBreakdown?.score))
            strain.append(.init(date: day, score: strainBreakdown.score))

            if let recScore = recBreakdown?.score {
                let readinessBreakdown = StateEngine.readiness(
                    inputs,
                    recoveryScore: recScore,
                    weeklyAdherence: 1.0,
                    recentStrain: priorDayStrain
                )
                readiness.append(.init(date: day, score: readinessBreakdown.score))
            } else {
                readiness.append(.init(date: day, score: nil))
            }

            // Energy stand-in: avg self-reported mood/energy scaled 1–5 → 0–100.
            if let selfReported = selfEnergy {
                let scaled = Int((Double(selfReported) / 5.0 * 100).rounded())
                energy.append(.init(date: day, score: scaled))
            } else {
                energy.append(.init(date: day, score: nil))
            }

            priorDayStrain = strainBreakdown.score
        }

        series = [
            .recovery: recovery,
            .readiness: readiness,
            .energy: energy,
            .strain: strain
        ]
    }

    // MARK: - Summary

    /// Aggregate stats for the chart card.
    func summary(for pillar: Pillar) -> Summary {
        let points = (series[pillar] ?? []).compactMap { p -> (Date, Int)? in
            guard let s = p.score else { return nil }
            return (p.date, s)
        }
        guard !points.isEmpty else {
            return Summary(average: nil, min: nil, max: nil, trendPerDay: nil)
        }
        let scores = points.map { $0.1 }
        let avg = Int(Double(scores.reduce(0, +)) / Double(scores.count))
        let minS = scores.min()
        let maxS = scores.max()
        return Summary(
            average: avg,
            min: minS,
            max: maxS,
            trendPerDay: trendSlope(points)
        )
    }

    // MARK: - Fetch helpers

    private func latestSleep(for day: Date, context: ModelContext) -> SleepSession? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let desc = FetchDescriptor<SleepSession>(
            predicate: #Predicate {
                $0.logicalDate >= start && $0.logicalDate < end
            },
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        return (try? context.fetch(desc))?.first
    }

    private func latestBiometric(for day: Date, context: ModelContext) -> BiometricSnapshot? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let desc = FetchDescriptor<BiometricSnapshot>(
            predicate: #Predicate {
                $0.logicalDate >= start && $0.logicalDate < end
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(desc))?.first
    }

    /// Sum step/workout/calorie load from ContextEvent rows on the day.
    /// Steps come from the latest BiometricSnapshot.stepsSoFar — that's a
    /// running total maintained by the Fitbit sync, so we use the last
    /// observation rather than summing event totals.
    private func dayLoad(for day: Date, context: ModelContext) -> StateEngine.DayLoadInputs {
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
        let workouts = (try? context.fetch(workoutDesc)) ?? []
        for w in workouts {
            load.workoutDurationMinutes += Int(w.value ?? 0)
            load.activeCalories += Int(w.secondaryValue ?? 0)
        }
        return load
    }

    /// Average of self-reported mood + energy events for the day, returns
    /// 1–5 integer (or nil when nothing logged).
    private func averageSelfEnergy(for day: Date, context: ModelContext) -> Int? {
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
        let avg = values.reduce(0, +) / Double(values.count)
        return Int(avg.rounded())
    }

    /// Naive least-squares slope in points/day. Returns nil when fewer
    /// than two scored points are available.
    private func trendSlope(_ points: [(Date, Int)]) -> Double? {
        guard points.count >= 2 else { return nil }
        let xs = points.indices.map { Double($0) }
        let ys = points.map { Double($0.1) }
        let n = Double(points.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denom = (n * sumX2 - sumX * sumX)
        guard denom != 0 else { return nil }
        return (n * sumXY - sumX * sumY) / denom
    }
}
