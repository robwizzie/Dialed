//
//  FoodLog.swift
//  Dialed
//
//  One list of everything you ate on a day — meals logged in Dialed
//  (photo, text, quick add) and older food-log entries — with edit,
//  delete and one-tap re-log. Totals on Home and Health read the same
//  records, so an edit here shows up everywhere.
//

import Foundation
import SwiftData

struct LoggedFood: Identifiable {
    enum Record {
        case meal(ContextEvent)
        case entry(FoodEntry)
    }

    let record: Record
    var id: String {
        switch record {
        case .meal(let e):  return "meal-\(e.id)"
        case .entry(let f): return "food-\(f.id)"
        }
    }
    var time: Date {
        switch record {
        case .meal(let e):  return e.timestamp
        case .entry(let f): return f.timestamp
        }
    }
    var name: String {
        switch record {
        case .meal(let e):  return e.mealName
        case .entry(let f): return f.name
        }
    }
    var calories: Double {
        switch record {
        case .meal(let e):  return e.value ?? 0
        case .entry(let f): return f.calories
        }
    }
    var protein: Double {
        switch record {
        case .meal(let e):  return e.secondaryValue ?? 0
        case .entry(let f): return f.proteinGrams
        }
    }
    var carbs: Double? {
        switch record {
        case .meal(let e):  return e.mealCarbs
        case .entry(let f): return f.carbsGrams
        }
    }
    var fat: Double? {
        switch record {
        case .meal(let e):  return e.mealFat
        case .entry(let f): return f.fatGrams
        }
    }
    /// Servings the numbers cover (1 unless you changed it).
    var servings: Double {
        switch record {
        case .meal(let e):  return e.mealServings ?? 1
        case .entry(let f): return f.servings ?? 1
        }
    }
}

/// What the editor hands back.
struct FoodDraft: Equatable {
    var name = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double?
    var fat: Double?
    var time = Date()
    /// Servings the numbers are for; changing it in the editor rescales them.
    var servings: Double = 1

    init() {}

    init(_ food: LoggedFood) {
        name = food.name == "Meal" ? "" : food.name
        calories = food.calories
        protein = food.protein
        carbs = food.carbs
        fat = food.fat
        time = food.time
        servings = food.servings
    }

    init(_ meal: SavedMeal) {
        name = meal.name
        calories = meal.calories
        protein = meal.proteinGrams
        carbs = meal.carbsGrams
        fat = meal.fatGrams
    }
}

@MainActor
enum FoodLog {
    static func entries(on day: Date, context: ModelContext) -> [LoggedFood] {
        let start = Calendar.current.startOfDay(for: day)
        return entries(from: start, to: Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start, context: context)
    }

    /// Everything logged in [start, end), oldest first: one fetch per kind.
    static func entries(from start: Date, to end: Date, context: ModelContext) -> [LoggedFood] {
        let meal = ContextEvent.Kind.meal.rawValue
        let events = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < end && $0.kindRaw == meal }))) ?? []
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.dayDate >= start && $0.dayDate < end }))) ?? []
        return (events.map { LoggedFood(record: .meal($0)) } + foods.map { LoggedFood(record: .entry($0)) })
            .sorted { $0.time < $1.time }
    }

    /// One food you've logged, folded across every time you had it.
    struct HistoryFood: Identifiable, Equatable {
        /// The most recent time's numbers, stamped now — ready to re-log.
        var draft: FoodDraft
        var count: Int
        /// Times in the last 60 days, for ranking your usuals.
        var recentCount: Int
        var lastEaten: Date
        var id: String { draft.name.lowercased() }
    }

    /// Every distinct food you've ever logged, most recent first. One
    /// fetch of each kind, so it's fine to call when a sheet opens.
    static func history(context: ModelContext, now: Date = Date()) -> [HistoryFood] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let recentStart = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        var index: [String: Int] = [:]
        var out: [HistoryFood] = []
        for food in entries(from: .distantPast, to: end, context: context).reversed() {
            guard food.name != "Meal", !food.name.isEmpty else { continue }
            let key = food.name.lowercased()
            let recent = food.time >= recentStart ? 1 : 0
            if let i = index[key] {
                out[i].count += 1
                out[i].recentCount += recent
            } else {
                var draft = FoodDraft(food)
                draft.time = now
                index[key] = out.count
                out.append(HistoryFood(draft: draft, count: 1, recentCount: recent, lastEaten: food.time))
            }
        }
        return out
    }

    /// What you log most lately: had at least twice, ranked by the last 60 days.
    static func usuals(_ history: [HistoryFood], limit: Int = 10) -> [HistoryFood] {
        history
            .filter { $0.count >= 2 && $0.recentCount >= 1 }
            .sorted { ($0.recentCount, $0.lastEaten) > ($1.recentCount, $1.lastEaten) }
            .prefix(limit)
            .map { $0 }
    }

    /// Distinct foods, most recent first — for one-tap re-logging. Reaches
    /// back through your whole history, not just the last two weeks.
    static func recents(context: ModelContext, limit: Int = 8) -> [FoodDraft] {
        history(context: context).prefix(limit).map(\.draft)
    }

    @discardableResult
    static func add(_ draft: FoodDraft, context: ModelContext) -> ContextEvent {
        let event = ContextEvent.meal(name: draft.name, calories: draft.calories, protein: draft.protein,
                                      carbs: draft.carbs, fat: draft.fat, at: draft.time, servings: draft.servings)
        context.insert(event)
        finish(context)
        HealthWriteBack.sync(event)
        return event
    }

    static func update(_ food: LoggedFood, with draft: FoodDraft, context: ModelContext) {
        switch food.record {
        case .meal(let e):
            e.updateMeal(name: draft.name, calories: draft.calories, protein: draft.protein,
                         carbs: draft.carbs, fat: draft.fat, time: draft.time, servings: draft.servings)
            HealthWriteBack.sync(e)
        case .entry(let f):
            let oldCalories = f.calories, oldProtein = f.proteinGrams
            f.name = draft.name.isEmpty ? f.name : draft.name
            f.calories = draft.calories
            f.proteinGrams = draft.protein
            f.carbsGrams = draft.carbs
            f.fatGrams = draft.fat
            f.timestamp = draft.time
            f.servings = draft.servings == 1 ? nil : draft.servings
            adjustDayLog(for: f, context: context, calories: draft.calories - oldCalories, protein: draft.protein - oldProtein)
        }
        finish(context)
    }

    static func delete(_ food: LoggedFood, context: ModelContext) {
        switch food.record {
        case .meal(let e):
            HealthWriteBack.remove(eventID: e.id)
            context.delete(e)
        case .entry(let f):
            adjustDayLog(for: f, context: context, calories: -f.calories, protein: -f.proteinGrams, removing: true)
            context.delete(f)
        }
        finish(context)
    }

    /// Keep the day's stored totals in step with an edited food-log entry.
    private static func adjustDayLog(for f: FoodEntry, context: ModelContext, calories: Double, protein: Double, removing: Bool = false) {
        let day = Calendar.current.startOfDay(for: f.dayDate)
        guard let log = (try? context.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.date == day })))?.first else { return }
        if let entries = log.foodEntries, entries.contains(where: { $0.id == f.id }) {
            if removing { log.foodEntries = entries.filter { $0.id != f.id } }
            log.updateNutritionTotals()
        } else {
            log.caloriesConsumed = max(0, log.caloriesConsumed + calories)
            log.proteinGrams = max(0, log.proteinGrams + protein)
        }
    }

    private static func finish(_ context: ModelContext) {
        try? context.save()
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }
}
