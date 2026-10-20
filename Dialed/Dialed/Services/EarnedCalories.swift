//
//  EarnedCalories.swift
//  Dialed
//
//  Every calorie you burn exercising goes back into the day's budget:
//  workouts your watch recorded (Apple Health, Google Health), the gym
//  sessions and cardio you logged, and fun activity you named. The same
//  session often shows up twice (the watch recorded the lift you also
//  logged), so overlapping entries count once — the watch's measured
//  number wins over an estimate. The combining is pure and tested; the
//  fetch is below.
//

import Foundation
import SwiftData
import HealthKit

enum EarnedCalories {

    struct Entry: Equatable, Identifiable {
        enum Source: Int, Comparable {
            /// Measured by a watch: the most trustworthy number.
            case watch = 0
            /// A heart-rate bout you named.
            case fun = 1
            /// Estimated from a session you logged.
            case logged = 2

            static func < (a: Source, b: Source) -> Bool { a.rawValue < b.rawValue }
        }

        var id: String
        var name: String
        var symbol: String
        var start: Date
        var end: Date
        var calories: Double
        var source: Source
    }

    struct Day: Equatable {
        var entries: [Entry] = []

        var earned: Double { entries.reduce(0) { $0 + $1.calories }.rounded() }
        var isEmpty: Bool { entries.isEmpty }

        /// "Strength, Pickleball" (first three).
        var sources: String {
            var names: [String] = []
            for e in entries where !names.contains(e.name) { names.append(e.name) }
            return names.count > 3 ? names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)" : names.joined(separator: ", ")
        }
    }

    /// One entry per real session: by source (watch first), skip anything
    /// that mostly overlaps one already counted, and trim the calories of
    /// anything that partly does.
    static func combine(_ candidates: [Entry]) -> Day {
        var kept: [Entry] = []
        for c in candidates.sorted(by: { ($0.source, $0.start) < ($1.source, $1.start) }) where c.calories > 0 {
            let span = DateInterval(start: c.start, end: max(c.start.addingTimeInterval(60), c.end))
            let share = ActivityAccounting.coveredShare(of: span, by: kept.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) })
            // Mostly the same session: count it once.
            guard share < 0.5 else { continue }
            // Partly the same (a walk inside a longer game, or the other way
            // round): keep only the part nothing else counted.
            var entry = c
            if share >= 0.1 { entry.calories = (c.calories * (1 - share)).rounded() }
            kept.append(entry)
        }
        return Day(entries: kept.sorted { $0.start < $1.start })
    }

    // MARK: - Estimates for logged sessions without a watch

    /// Lifting ≈ 5 METs (moderate weight training).
    static func strengthCalories(minutes: Double, weightLbs: Double) -> Double {
        (5 * 3.5 * weightLbs * 0.4536 / 200 * minutes).rounded()
    }

    /// Foot cardio from distance (≈0.63 cal/lb/mi running, 0.3 walking);
    /// otherwise from time.
    static func cardioCalories(kind: String, minutes: Double?, miles: Double?, weightLbs: Double) -> Double {
        let k = kind.lowercased()
        if let miles, miles > 0, k.contains("run") || k.contains("walk") {
            return (miles * weightLbs * (k.contains("run") ? 0.63 : 0.3)).rounded()
        }
        guard let minutes, minutes > 0 else { return 0 }
        let mets: Double = k.contains("run") ? 9 : k.contains("walk") ? 3.5 : k.contains("bike") ? 7 : 6
        return (mets * 3.5 * weightLbs * 0.4536 / 200 * minutes).rounded()
    }
}

// MARK: - Fetch

extension EarnedCalories {

    @MainActor
    static func day(_ date: Date = Date(), context: ModelContext) async -> Day {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        let weight = await latestWeight() ?? 200
        var candidates: [Entry] = []

        // 1. Workouts any app recorded in Health (watch, Mile A Day…). Ones
        // that didn't save calories are estimated, so they still count once.
        for w in await WorkoutDetector.workouts(on: date, context: context) {
            let cal: Double
            if let measured = w.calories, measured > 0 {
                cal = Double(measured)
            } else if w.kind == .strength {
                cal = strengthCalories(minutes: w.minutes, weightLbs: weight)
            } else {
                cal = cardioCalories(kind: WorkoutDetector.title(for: w.kind), minutes: w.minutes, miles: w.miles, weightLbs: weight)
            }
            guard cal > 0 else { continue }
            candidates.append(Entry(id: "watch-\(w.id)", name: w.title,
                                    symbol: w.isCardio ? WorkoutLoggerView.cardioSymbol(WorkoutDetector.title(for: w.kind))
                                        : w.kind == .strength ? "dumbbell.fill" : ActiveBouts.symbol(for: w.title),
                                    start: w.start, end: w.end, calories: cal, source: .watch))
        }

        // 2. Fun activity you named.
        let workout = ContextEvent.Kind.workout.rawValue, fun = FunActivityService.subtype
        let funDesc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.kindRaw == workout && $0.subtype == fun && $0.timestamp >= start && $0.timestamp < end })
        for e in (try? context.fetch(funDesc)) ?? [] {
            let name = e.text ?? "Activity"
            candidates.append(Entry(id: "fun-\(e.id)", name: name, symbol: ActiveBouts.symbol(for: name),
                                    start: e.timestamp, end: e.timestamp.addingTimeInterval((e.value ?? 0) * 60),
                                    calories: e.secondaryValue ?? 0, source: .fun))
        }

        // 3. Sessions you logged (estimated).
        let logDesc = FetchDescriptor<PlanWorkoutLog>(predicate: #Predicate { $0.date >= start && $0.date < end })
        for log in (try? context.fetch(logDesc)) ?? [] {
            let kind = WorkoutProgram.Session.Kind(rawValue: log.kindRaw)
            if kind == .bike || kind == .walk {
                let minutes = log.durationMinutes ?? log.endedAt.flatMap { e in log.startedAt.map { e.timeIntervalSince($0) / 60 } }
                let cal = cardioCalories(kind: kind == .bike ? "Bike" : "Walk", minutes: minutes, miles: log.distanceMiles, weightLbs: weight)
                let s = log.startedAt ?? log.savedAt.addingTimeInterval(-(minutes ?? 30) * 60)
                candidates.append(Entry(id: "log-\(log.id)", name: log.title, symbol: kind == .bike ? "figure.outdoor.cycle" : "figure.walk",
                                        start: s, end: log.endedAt ?? s.addingTimeInterval((minutes ?? 30) * 60),
                                        calories: cal, source: .logged))
                continue
            }
            // Lifting: the time you gave it, else ~2.5 min per finished set.
            let doneSets = PlanWorkoutLogStore.sets(for: log.id, context: context).filter(\.completed).count
            if let s = log.startedAt, let e = log.endedAt, e > s {
                candidates.append(Entry(id: "log-\(log.id)", name: log.title, symbol: "dumbbell.fill", start: s, end: e,
                                        calories: strengthCalories(minutes: e.timeIntervalSince(s) / 60, weightLbs: weight),
                                        source: .logged))
            } else if doneSets > 0 {
                let minutes = max(15, Double(doneSets) * 2.5)
                let e = log.savedAt
                candidates.append(Entry(id: "log-\(log.id)", name: log.title, symbol: "dumbbell.fill",
                                        start: e.addingTimeInterval(-minutes * 60), end: e,
                                        calories: strengthCalories(minutes: minutes, weightLbs: weight), source: .logged))
            }
            if let kindName = log.cardioKind {
                let minutes = log.cardioMinutes ?? 15
                // Cardio usually comes right before the lift.
                let e = log.startedAt ?? log.savedAt
                candidates.append(Entry(id: "log-cardio-\(log.id)", name: kindName, symbol: WorkoutLoggerView.cardioSymbol(kindName),
                                        start: e.addingTimeInterval(-minutes * 60), end: e,
                                        calories: cardioCalories(kind: kindName, minutes: log.cardioMinutes, miles: log.cardioMiles, weightLbs: weight),
                                        source: .logged))
            }
        }

        return combine(candidates)
    }

    private static func latestWeight() async -> Double? {
        try? await HealthKitManager.shared.fetchLatest(.bodyMass, unit: .pound(), withinDays: 30)?.value
    }
}
