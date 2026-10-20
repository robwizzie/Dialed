//
//  RacePaceLoader.swift
//  Dialed
//
//  Feeds RacePace from the app's data: your challenge start and trend
//  weight, your friend's weigh-ins, and the last week of food and exercise.
//

import Foundation
import SwiftData

extension RacePace {

    /// Everything the pace card shows.
    struct Report: Equatable {
        var result: Result
        var friendName: String
        var end: Date
        var weight: Double
        /// Daily calories that hold the needed pace (before exercise).
        var targetCalories: Double
    }

    @MainActor
    static func report(challenge: WeightChallenge, readings: [WeightReading], context: ModelContext,
                       now: Date = Date()) async -> Report? {
        let calendar = Calendar.current
        let series = WeightChallengeEngine.dailySeries(readings, calendar: calendar)
        guard let latest = series.last, now < challenge.endDate else { return nil }
        let start = calendar.startOfDay(for: challenge.startDate)
        let yourStart = challenge.startWeightOverride
            ?? series.first(where: { $0.day >= start })?.pounds
            ?? series.last(where: { $0.day < start })?.pounds
            ?? latest.pounds

        // Last seven full days of food and exercise.
        var days: [(eaten: Double, earned: Double)] = []
        for back in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now)) else { continue }
            let eaten = FoodLog.entries(on: day, context: context).reduce(0) { $0 + $1.calories }
            let earned = eaten > 300 ? await EarnedCalories.day(day, context: context).earned : 0
            days.append((eaten, earned))
        }

        let inputs = Inputs(
            scoring: challenge.scoring, yourStart: yourStart, yourTrend: latest.trend,
            yourTrendRate: trendRate(series, now: now, calendar: calendar),
            yourFoodRate: foodRate(days: days, weight: latest.trend),
            friendStart: challenge.friendStartWeight,
            friendWeighIns: challenge.friendWeighIns.map { ($0.date, $0.pounds) },
            challengeStart: challenge.startDate, end: challenge.endDate, now: now)
        let result = compute(inputs, calendar: calendar)
        return Report(result: result, friendName: challenge.friendDisplayName, end: challenge.endDate,
                      weight: latest.trend, targetCalories: calories(for: result.needed, weight: latest.trend))
    }
}
