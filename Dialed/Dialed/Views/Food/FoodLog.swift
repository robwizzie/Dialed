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
}

/// What the editor hands back.
struct FoodDraft: Equatable {
    var name = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double?
    var fat: Double?
    var time = Date()

    init() {}

    init(_ food: LoggedFood) {
        name = food.name == "Meal" ? "" : food.name
        calories = food.calories
        protein = food.protein
        carbs = food.carbs
        fat = food.fat
        time = food.time
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
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let meal = ContextEvent.Kind.meal.rawValue
        let events = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < end && $0.kindRaw == meal }))) ?? []
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.dayDate >= start && $0.dayDate < end }))) ?? []
        return (events.map { LoggedFood(record: .meal($0)) } + foods.map { LoggedFood(record: .entry($0)) })
            .sorted { $0.time < $1.time }
    }

    /// Distinct foods from the last two weeks, most recent first — for one-tap re-logging.
    static func recents(context: ModelContext, limit: Int = 8) -> [FoodDraft] {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        var seen = Set<String>()
        var out: [FoodDraft] = []
        for day in stride(from: 0, through: 14, by: 1) {
            guard let d = Calendar.current.date(byAdding: .day, value: -day, to: Date()), d >= since else { continue }
            for food in entries(on: d, context: context).reversed() {
                let key = food.name.lowercased()
                guard food.name != "Meal", !seen.contains(key) else { continue }
                seen.insert(key)
                var draft = FoodDraft(food)
                draft.time = Date()
                out.append(draft)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    static func add(_ draft: FoodDraft, context: ModelContext) {
        context.insert(ContextEvent.meal(name: draft.name, calories: draft.calories, protein: draft.protein,
                                         carbs: draft.carbs, fat: draft.fat, at: draft.time))
        finish(context)
    }

    static func update(_ food: LoggedFood, with draft: FoodDraft, context: ModelContext) {
        switch food.record {
        case .meal(let e):
            e.updateMeal(name: draft.name, calories: draft.calories, protein: draft.protein,
                         carbs: draft.carbs, fat: draft.fat, time: draft.time)
        case .entry(let f):
            let oldCalories = f.calories, oldProtein = f.proteinGrams
            f.name = draft.name.isEmpty ? f.name : draft.name
            f.calories = draft.calories
            f.proteinGrams = draft.protein
            f.carbsGrams = draft.carbs
            f.fatGrams = draft.fat
            f.timestamp = draft.time
            adjustDayLog(for: f, context: context, calories: draft.calories - oldCalories, protein: draft.protein - oldProtein)
        }
        finish(context)
    }

    static func delete(_ food: LoggedFood, context: ModelContext) {
        switch food.record {
        case .meal(let e):
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
