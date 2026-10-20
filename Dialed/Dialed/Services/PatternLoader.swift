//
//  PatternLoader.swift
//  Dialed
//
//  Builds the last five weeks of days for PatternFinder from what Dialed
//  already has: food (Dialed meals, the food log and Apple Health
//  calories), the mile history, synced sleep, workout logs, drinks and the
//  scale. Results are cached for half an hour so Home and the weekly
//  review can both ask without redoing the work.
//

import Foundation
import SwiftData
import HealthKit

@MainActor
enum PatternLoader {
    static let lookbackDays = 35

    private static var cache: (at: Date, patterns: [PatternFinder.Pattern])?

    static func patterns(context: ModelContext, force: Bool = false) async -> [PatternFinder.Pattern] {
        if !force, let cache, Date().timeIntervalSince(cache.at) < 30 * 60 { return cache.patterns }
        let days = await days(context: context)
        let found = PatternFinder.find(days, mileGoal: MileSettings.load().goalMiles)
        cache = (Date(), found)
        return found
    }

    /// Completed days only (today is still in progress).
    static func days(context: ModelContext, now: Date = Date()) async -> [PatternFinder.Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return [] }

        async let hkEnergy = try? HealthKitManager.shared.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: lookbackDays + 1)
        async let hkProtein = try? HealthKitManager.shared.fetchDailySums(.dietaryProtein, unit: .gram(), days: lookbackDays + 1)
        let readings = await WeightDataSource.readings(context: context, since: start)
        let energyByDay = await hkEnergy ?? [:]
        let proteinByDay = await hkProtein ?? [:]

        let logs = (try? context.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.date >= start && $0.date < today }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < today }))) ?? []
        let sleeps = (try? context.fetch(FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < today }))) ?? []
        let workoutLogs = (try? context.fetch(FetchDescriptor<PlanWorkoutLog>(
            predicate: #Predicate { $0.date >= start && $0.date < today }))) ?? []
        let doneKeys = WeeklyReview.workoutKeys(UserDefaults.standard.string(forKey: WorkoutPlanStore.doneKey) ?? "")
        let milesByDay = MileHistory.load()?.milesByDay ?? [:]
        let weightByDay = Dictionary(WeightChallengeEngine.dailySeries(readings, calendar: calendar).map { ($0.day, $0.pounds) },
                                     uniquingKeysWith: { a, _ in a })

        let mealKind = ContextEvent.Kind.meal.rawValue
        let alcoholKind = ContextEvent.Kind.alcohol.rawValue
        let workoutKind = ContextEvent.Kind.workout.rawValue
        let workoutDays = Set(workoutLogs.map { calendar.startOfDay(for: $0.date) })

        return WeeklyReview.days(from: start, to: calendar.date(byAdding: .day, value: -1, to: today) ?? today, calendar: calendar).map { d in
            let log = logs.first { calendar.isDate($0.date, inSameDayAs: d) }
            let dayEvents = events.filter { calendar.isDate($0.logicalDate, inSameDayAs: d) }
            let meals = dayEvents.filter { $0.kindRaw == mealKind }
            let calories = max((log?.caloriesConsumed ?? 0) + meals.reduce(0) { $0 + ($1.value ?? 0) }, energyByDay[d] ?? 0)
            let protein = max((log?.proteinGrams ?? 0) + meals.reduce(0) { $0 + ($1.secondaryValue ?? 0) }, proteinByDay[d] ?? 0)
            let night = sleeps.filter { calendar.isDate($0.logicalDate, inSameDayAs: d) }.max { $0.asleepMinutes < $1.asleepMinutes }
            let sleepMinutes = night.map { Double($0.asleepMinutes) } ?? log?.sleepDurationMinutes.map(Double.init)
            let lastMeal = FoodLog.entries(on: d, context: context).last?.time
            return PatternFinder.Day(
                date: d,
                calories: calories > 0 ? calories : nil,
                protein: protein > 0 ? protein : nil,
                miles: milesByDay[d],
                sleepMinutes: (sleepMinutes ?? 0) > 0 ? sleepMinutes : nil,
                bedtime: night?.startTime,
                lastMeal: lastMeal,
                workout: workoutDays.contains(d) || doneKeys.contains(WeeklyReview.dayKey(d, calendar: calendar))
                    || dayEvents.contains { $0.kindRaw == workoutKind },
                weight: weightByDay[d],
                drinks: dayEvents.filter { $0.kindRaw == alcoholKind }.reduce(0) { $0 + ($1.value ?? 0) }
            )
        }
    }
}
