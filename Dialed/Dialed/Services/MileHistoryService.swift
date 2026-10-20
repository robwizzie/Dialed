//
//  MileHistoryService.swift
//  Dialed
//
//  Works out every day of the daily mile from Apple Health and keeps it
//  in the App Group (MileHistory) for Home, the history calendar and the
//  widgets. Each day takes the bigger of Health's walking + running
//  distance and your on-foot workouts (several add up), falling back to
//  a step estimate with your stride.
//
//  Home refreshes the last two weeks on every pull; "Recalibrate" in
//  Settings → Mile a day re-reads everything from the history start.
//

import Foundation
import SwiftData

@MainActor
enum MileHistoryService {
    /// Days Home re-reads on a normal refresh (late-synced workouts land).
    static let recentDays = 14
    /// Never look back further than this.
    static let maxDays = 730

    /// Where history starts: the date you picked, else your challenge's
    /// start, else 90 days back.
    static func defaultStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        if let start = MileSettings.load().historyStart { return calendar.startOfDay(for: start) }
        if let challenge = WeightChallenge.load() { return calendar.startOfDay(for: challenge.startDate) }
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -89, to: now) ?? now)
    }

    /// Refresh the recent days — or everything when there's no history
    /// yet or its start moved — and save.
    @discardableResult
    static func update(context: ModelContext, extraSteps: [Date: Double] = [:], now: Date = Date()) async -> MileHistory {
        let start = defaultStart(now: now)
        if var history = MileHistory.load(), history.start == start {
            let calendar = Calendar.current
            let recentStart = max(start, calendar.date(byAdding: .day, value: -(recentDays - 1),
                                                       to: calendar.startOfDay(for: now)) ?? start)
            history.merge(await days(from: recentStart, now: now, context: context, extraSteps: extraSteps))
            history.updatedAt = now
            history.save()
            return history
        }
        return await rebuild(from: start, context: context, extraSteps: extraSteps, now: now)
    }

    /// Re-read every day from `start` (Settings → Recalibrate).
    @discardableResult
    static func rebuild(from start: Date, context: ModelContext, extraSteps: [Date: Double] = [:],
                        now: Date = Date()) async -> MileHistory {
        let calendar = Calendar.current
        let earliest = calendar.date(byAdding: .day, value: -(maxDays - 1), to: calendar.startOfDay(for: now)) ?? start
        let from = max(calendar.startOfDay(for: start), earliest)
        var history = MileHistory(start: from, days: [], updatedAt: now)
        history.merge(await days(from: from, now: now, context: context, extraSteps: extraSteps))
        history.save()
        return history
    }

    private static func days(from start: Date, now: Date, context: ModelContext,
                             extraSteps: [Date: Double]) async -> [MileDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let count = max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
        let health = HealthKitManager.shared

        async let distance = try? health.fetchDailySums(.distanceWalkingRunning, unit: .mile(), days: count)
        async let steps = try? health.fetchDailySums(.stepCount, unit: .count(), days: count)
        async let workouts = health.fetchFootWorkoutMiles(
            from: start, to: calendar.date(byAdding: .day, value: 1, to: today) ?? now)
        let distanceByDay = await distance ?? [:]
        let stepsByDay = await steps ?? [:]
        let workoutsByDay = await workouts

        // Steps the app logged itself (and the Pixel Watch, via Home).
        var loggedSteps: [Date: Double] = extraSteps
        let descriptor = FetchDescriptor<DayLog>(predicate: #Predicate { $0.date >= start })
        for log in (try? context.fetch(descriptor)) ?? [] {
            let d = calendar.startOfDay(for: log.date)
            loggedSteps[d] = max(loggedSteps[d] ?? 0, Double(log.steps ?? 0))
        }

        // Runs and walks you logged yourself (treadmill with no watch).
        var logged: [Date: (miles: Double, ran: Bool)] = [:]
        for log in (try? context.fetch(FetchDescriptor<PlanWorkoutLog>(predicate: #Predicate { $0.date >= start }))) ?? [] {
            let d = calendar.startOfDay(for: log.date)
            var miles = 0.0, ran = false
            if let kind = log.cardioKind, kind == "Run" || kind == "Walk", let mi = log.cardioMiles {
                miles += mi
                ran = kind == "Run"
            }
            if log.kindRaw == WorkoutProgram.Session.Kind.walk.rawValue, let mi = log.distanceMiles { miles += mi }
            guard miles > 0 else { continue }
            let prior = logged[d] ?? (0, false)
            logged[d] = (prior.miles + miles, prior.ran || ran)
        }

        // Learn your stride from days Health has both.
        var settings = MileSettings.load()
        if let learned = MileADay.learnStride(distanceByDay.compactMap { day, miles in
            stepsByDay[day].map { (steps: $0, miles: miles) }
        }), learned != settings.learnedStepsPerMile {
            settings.learnedStepsPerMile = learned
            settings.save()
        }

        return (0..<count).compactMap { offset -> MileDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let w = workoutsByDay[day]
            let mine = logged[day]
            // The same run can be both logged and watch-recorded: take the larger, don't add.
            let footMiles = max(w?.miles ?? 0, mine?.miles ?? 0)
            let daySteps = Int(max(stepsByDay[day] ?? 0, loggedSteps[day] ?? 0))
            let r = MileADay.resolve(distance: distanceByDay[day], workoutMiles: footMiles,
                                     steps: daySteps, stepsPerMile: settings.stepsPerMile)
            return MileDay(date: day, miles: r.miles, workoutMiles: footMiles,
                           workouts: max(w?.count ?? 0, mine == nil ? 0 : 1),
                           ran: (w?.ran ?? false) || (mine?.ran ?? false), source: r.source)
        }
    }
}
