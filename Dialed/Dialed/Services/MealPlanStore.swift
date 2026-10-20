//
//  MealPlanStore.swift
//  Dialed
//
//  Keeps this week's meal plan: built from your calorie and protein
//  targets (and the foods you already log), rebuilt when the week runs
//  out or your targets move, with swaps, one-tap logging and the grocery
//  list's check marks saved in UserDefaults.
//

import Foundation
import SwiftData

@MainActor
enum MealPlanStore {
    private static let planKey = "mealPlan.week"
    private static let checkedKey = "mealPlan.checked"
    private static let loggedKey = "mealPlan.logged"
    static let didChange = Notification.Name("MealPlanDidChange")

    // MARK: - Plan

    static var targets: (calories: Double, protein: Double) {
        let s = UserSettings.load()
        return (CalorieTarget.current(settings: s, weight: s.currentWeight), s.proteinTargetGrams)
    }

    /// This week's plan; a new one when the old one has run out or your
    /// targets changed by more than 100 calories / 10 g protein.
    static func current(context: ModelContext, now: Date = Date()) -> WeekMealPlanner.WeekPlan {
        let calendar = Calendar.current
        let t = targets
        if let saved = load(),
           saved.days.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }),
           abs(saved.calories - t.calories) < 100, abs(saved.protein - t.protein) < 10 {
            return saved
        }
        return build(context: context, seed: load()?.seed ?? 0, now: now)
    }

    @discardableResult
    static func regenerate(context: ModelContext, now: Date = Date()) -> WeekMealPlanner.WeekPlan {
        let plan = build(context: context, seed: (load()?.seed ?? 0) + 1, now: now)
        UserDefaults.standard.removeObject(forKey: checkedKey)
        return plan
    }

    @discardableResult
    static func swap(day: Int, slot: WeekMealPlanner.Slot, context: ModelContext) -> WeekMealPlanner.WeekPlan {
        let plan = WeekMealPlanner.swap(current(context: context), day: day, slot: slot)
        save(plan)
        return plan
    }

    private static func build(context: ModelContext, seed: Int, now: Date) -> WeekMealPlanner.WeekPlan {
        let t = targets
        let names = FoodLog.recents(context: context, limit: 20).map(\.name) + SavedMealsManager.load().map(\.name)
        let plan = WeekMealPlanner.week(start: now, calories: t.calories, protein: t.protein,
                                        preferred: WeekMealPlanner.preferredFoods(fromNames: names), seed: seed)
        save(plan)
        return plan
    }

    private static func load() -> WeekMealPlanner.WeekPlan? {
        guard let data = UserDefaults.standard.data(forKey: planKey) else { return nil }
        return try? JSONDecoder().decode(WeekMealPlanner.WeekPlan.self, from: data)
    }

    private static func save(_ plan: WeekMealPlanner.WeekPlan) {
        if let data = try? JSONEncoder().encode(plan) { UserDefaults.standard.set(data, forKey: planKey) }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: - Logging

    private static func logKey(_ date: Date, _ slot: WeekMealPlanner.Slot) -> String {
        WakeSchedule.key(date) + "|" + slot.rawValue
    }

    static func isLogged(_ meal: WeekMealPlanner.Meal, on date: Date) -> Bool {
        (UserDefaults.standard.stringArray(forKey: loggedKey) ?? []).contains(logKey(date, meal.slot))
    }

    /// Log a planned meal now (or at its slot time on another day).
    static func log(_ meal: WeekMealPlanner.Meal, on date: Date, context: ModelContext) {
        var draft = FoodDraft()
        draft.name = meal.name
        draft.calories = meal.calories
        draft.protein = meal.protein
        draft.carbs = meal.carbs
        draft.fat = meal.fat
        let calendar = Calendar.current
        draft.time = calendar.isDateInToday(date)
            ? Date()
            : calendar.date(bySettingHour: meal.slot.hour, minute: 0, second: 0, of: date) ?? date
        FoodLog.add(draft, context: context)
        var logged = UserDefaults.standard.stringArray(forKey: loggedKey) ?? []
        logged.append(logKey(date, meal.slot))
        UserDefaults.standard.set(Array(logged.suffix(120)), forKey: loggedKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: - Groceries

    static var checked: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: checkedKey) ?? [])
    }

    static func toggle(_ item: String) {
        var set = checked
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
        UserDefaults.standard.set(set.sorted(), forKey: checkedKey)
    }
}
