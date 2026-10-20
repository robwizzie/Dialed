//
//  ProteinPacingLoader.swift
//  Dialed
//
//  Feeds ProteinPacing from the food log: your last three weeks of meals
//  for the curve (learned once a day) and today's last meal time.
//

import Foundation
import SwiftData

extension ProteinPacing {

    @MainActor private static var cached: (day: Date, curve: Curve)?

    /// Every logged food with protein over the last `days` days and today.
    @MainActor
    static func recentMeals(context: ModelContext, now: Date = Date(), days: Int = 21) -> [Meal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0...days).flatMap { back -> [Meal] in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return [] }
            return FoodLog.entries(on: day, context: context)
                .filter { $0.protein > 0 }
                .map { Meal(date: $0.time, protein: $0.protein) }
        }
    }

    /// Your curve, relearned at most once a day.
    @MainActor
    static func curve(context: ModelContext, now: Date = Date()) -> Curve {
        let today = Calendar.current.startOfDay(for: now)
        if let cached, cached.day == today { return cached.curve }
        let curve = learn(recentMeals(context: context, now: now), now: now)
        cached = (today, curve)
        return curve
    }

    /// When you last ate today (from the food log).
    @MainActor
    static func lastMeal(context: ModelContext, now: Date = Date()) -> Date? {
        FoodLog.entries(on: now, context: context).map(\.time).filter { $0 <= now }.max()
    }
}
