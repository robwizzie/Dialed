//
//  RecentSuggestions.swift
//  Dialed
//
//  Fills DaySuggestions from Health and the app's logs: for any day,
//  the heart-rate stretches still waiting for a name and the watch gym
//  sessions with no log. Home's "From recent days" card looks back six
//  days, cached for a few minutes since every day is a Health query.
//

import Foundation
import SwiftData

@MainActor
enum RecentSuggestions {
    private static let dismissedKey = "suggestions.dismissedWorkouts"
    private static var cache: (at: Date, items: [DaySuggestions.Item])?

    /// What's waiting from today and the `days` before it.
    static func recent(context: ModelContext, days: Int = 6, force: Bool = false, now: Date = Date()) async -> [DaySuggestions.Item] {
        if !force, let cache, now.timeIntervalSince(cache.at) < 10 * 60 { return cache.items }
        let calendar = Calendar.current
        var items: [DaySuggestions.Item] = []
        for back in 0...max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now)) else { continue }
            items += await forDay(day, context: context)
        }
        let sorted = items.sorted { $0.start > $1.start }
        cache = (now, sorted)
        return sorted
    }

    /// What's waiting from one day.
    static func forDay(_ date: Date, context: ModelContext) async -> [DaySuggestions.Item] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let active = await FunActivityService.day(day, context: context)
        let workouts = await WorkoutDetector.workouts(on: day, context: context)
        let logged: Set<Date> = PlanWorkoutLogStore.log(for: WorkoutPlanStore.key(day), context: context) == nil ? [] : [day]
        return DaySuggestions.pending(bouts: active.unnamed, workouts: workouts, loggedDays: logged,
                                      dismissed: dismissed, calendar: calendar)
    }

    /// "Not this one": bouts go through FunActivityService, watch sessions here.
    static func dismiss(_ item: DaySuggestions.Item) {
        switch item.kind {
        case .activity:
            if let bout = item.bout { FunActivityService.dismiss(bout) }
        case .workout:
            guard let w = item.workout else { break }
            var ids = dismissed
            ids.insert(w.id)
            UserDefaults.standard.set(Array(Array(ids).suffix(200)), forKey: dismissedKey)
        }
        invalidate()
    }

    static func invalidate() { cache = nil }

    private static var dismissed: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }
}
