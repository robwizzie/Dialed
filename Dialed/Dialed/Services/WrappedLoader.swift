//
//  WrappedLoader.swift
//  Dialed
//
//  Gathers what Dialed Wrapped needs: your challenge, weigh-ins, miles,
//  sets, workouts, food-log days and fun activity.
//

import Foundation
import SwiftData

@MainActor
enum WrappedLoader {

    static func inputs(context: ModelContext, now: Date = Date()) async -> WrappedBuilder.Inputs? {
        guard let challenge = WeightChallenge.load() else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: challenge.startDate)
        let last = min(calendar.startOfDay(for: now), calendar.startOfDay(for: challenge.endDate))
        let since = calendar.date(byAdding: .day, value: -30, to: start) ?? start
        let readings = await WeightDataSource.readings(context: context, since: since)

        let sets = PlanWorkoutLogStore.allSets(context: context)
            .filter { $0.completed && $0.reps > 0 }
            .map { StrengthMilestones.SetRecord(exercise: $0.exerciseName, date: $0.date, weight: $0.weightLbs, reps: $0.reps) }
        let logs = (try? context.fetch(FetchDescriptor<PlanWorkoutLog>(predicate: #Predicate { $0.date >= start }))) ?? []

        var foodDays = Set<Date>()
        var day = start
        while day <= last {
            if !FoodLog.entries(on: day, context: context).isEmpty { foodDays.insert(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let workout = ContextEvent.Kind.workout.rawValue, fun = FunActivityService.subtype
        let funEvents = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.kindRaw == workout && $0.subtype == fun && $0.timestamp >= start }))) ?? []

        return WrappedBuilder.Inputs(
            friendName: challenge.friendDisplayName,
            start: challenge.startDate, end: challenge.endDate, now: now, scoring: challenge.scoring,
            series: WeightChallengeEngine.dailySeries(readings, calendar: calendar),
            startWeightOverride: challenge.startWeightOverride,
            friendStart: challenge.friendStartWeight,
            friendWeighIns: challenge.friendWeighIns.map { ($0.date, $0.pounds) },
            milesByDay: MileHistory.load()?.milesByDay ?? [:],
            mileGoal: MileSettings.load().goalMiles,
            sets: sets,
            workoutDays: Set(logs.map { calendar.startOfDay(for: $0.date) }),
            foodLoggedDays: foodDays,
            funActivities: funEvents.map { ($0.text ?? "Activity", $0.timestamp, $0.value ?? 0) })
    }
}
