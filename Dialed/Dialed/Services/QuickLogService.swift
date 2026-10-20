//
//  QuickLogService.swift
//  Dialed
//
//  The one path every quick log takes — in-app buttons, Siri & Shortcuts,
//  the Action button and taps on the home-screen widget. Going through
//  here guarantees the row is saved, mirrored to Apple Health and
//  announced with `dialedDataDidChange`, whoever asked for it.
//

import Foundation
import SwiftData
import HealthKit

@MainActor
enum QuickLogService {

    /// Today's intake against targets — what Siri reads out and the
    /// widget shows.
    struct Totals: Equatable {
        var waterOz: Double
        var waterTargetOz: Double
        var calories: Double
        var calorieTarget: Double
        var protein: Double
        var proteinTarget: Double

        var waterLeftOz: Double { max(0, waterTargetOz - waterOz) }
        var proteinLeft: Double { max(0, proteinTarget - protein) }
        var caloriesLeft: Double { calorieTarget - calories }

        /// "64 oz water, 120 g protein, 900 calories left"
        var spokenSummary: String {
            let calorieText = caloriesLeft >= 0
                ? "\(Int(caloriesLeft.rounded())) calories left"
                : "\(Int((-caloriesLeft).rounded())) calories over"
            return "\(Int(waterOz.rounded())) oz water, \(Int(protein.rounded())) g protein, \(calorieText)"
        }
    }

    // MARK: - Water

    @discardableResult
    static func logWater(_ ounces: Double, at time: Date = Date(), context: ModelContext) -> ContextEvent {
        let event = ContextEvent.water(ounces, at: time)
        context.insert(event)
        try? context.save()
        HealthWriteBack.sync(event)
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
        return event
    }

    // MARK: - Meals

    @discardableResult
    static func logMeal(_ draft: FoodDraft, context: ModelContext) -> ContextEvent {
        // FoodLog saves, mirrors to Health and posts the change.
        FoodLog.add(draft, context: context)
    }

    static func favorites() -> [SavedMeal] {
        SavedMealsManager.load()
    }

    static func favorite(id: UUID) -> SavedMeal? {
        favorites().first { $0.id == id }
    }

    /// Exact (case-insensitive) name first, then the first name containing it.
    static func favorite(named name: String) -> SavedMeal? {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return nil }
        let all = favorites()
        return all.first { $0.name.lowercased() == query }
            ?? all.first { $0.name.lowercased().contains(query) }
    }

    @discardableResult
    static func logFavorite(_ meal: SavedMeal, at time: Date = Date(), context: ModelContext) -> ContextEvent {
        var draft = FoodDraft(meal)
        draft.time = time
        return logMeal(draft, context: context)
    }

    // MARK: - Totals

    /// What's logged in Dialed today (meals, water, older food-log totals).
    /// Pass Apple Health sums to merge them the way Home does: devices
    /// report running water totals with quick logs on top; for food the
    /// larger of Dialed and Health wins.
    static func todayTotals(
        context: ModelContext,
        now: Date = Date(),
        healthWaterOz: Double = 0,
        healthCalories: Double = 0,
        healthProtein: Double = 0
    ) -> Totals {
        let calendar = Calendar.current
        let settings = UserSettings.load()
        let logical = calendar.logicalStartOfDay(for: now)
        let today = calendar.startOfDay(for: now)

        let events = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate == logical }))) ?? []
        let dayLog = (try? context.fetch(FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date == today })))?.first

        let water = events.filter { $0.kind == .water }.reduce(0) { $0 + ($1.value ?? 0) }
        let meals = events.filter { $0.kind == .meal }
        let mealCalories = meals.reduce(0) { $0 + ($1.value ?? 0) }
        let mealProtein = meals.reduce(0) { $0 + ($1.secondaryValue ?? 0) }

        let deviceWater = max(healthWaterOz, dayLog?.waterOz ?? 0)
        let calories = max((dayLog?.caloriesConsumed ?? 0) + mealCalories, healthCalories)
        let protein = max((dayLog?.proteinGrams ?? 0) + mealProtein, healthProtein)

        return Totals(
            waterOz: deviceWater + water,
            waterTargetOz: settings.waterTargetOz,
            calories: calories,
            calorieTarget: CalorieTarget.current(settings: settings, weight: settings.currentWeight),
            protein: protein,
            proteinTarget: settings.proteinTargetGrams
        )
    }

    /// `todayTotals` with Apple Health folded in (best effort — no access
    /// just means Dialed's own numbers). Health reads already skip what
    /// Dialed wrote, so nothing is counted twice.
    static func todayTotalsIncludingHealth(context: ModelContext, now: Date = Date()) async -> Totals {
        let health = HealthKitManager.shared
        let today = Calendar.current.startOfDay(for: now)
        let water = (try? await health.fetchDailySums(.dietaryWater, unit: .fluidOunceUS(), days: 1))?[today] ?? 0
        let energy = (try? await health.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: 1))?[today] ?? 0
        let protein = (try? await health.fetchDailySums(.dietaryProtein, unit: .gram(), days: 1))?[today] ?? 0
        return todayTotals(context: context, now: now, healthWaterOz: water, healthCalories: energy, healthProtein: protein)
    }
}
