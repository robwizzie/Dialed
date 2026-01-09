//
//  FoodEntry.swift
//  Dialed
//
//  Food/meal logging entry
//

import Foundation
import SwiftData

@Model
final class FoodEntry {
    var id: UUID
    var dayDate: Date
    var timestamp: Date
    var name: String
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double?
    var fatGrams: Double?

    // For saved meals / quick add
    var isSavedMeal: Bool

    init(
        dayDate: Date,
        name: String,
        calories: Double,
        proteinGrams: Double,
        carbsGrams: Double? = nil,
        fatGrams: Double? = nil,
        isSavedMeal: Bool = false
    ) {
        self.id = UUID()
        self.dayDate = dayDate
        self.timestamp = Date()
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.isSavedMeal = isSavedMeal
    }
}

// Saved meal template (stored in UserDefaults)
struct SavedMeal: Codable, Identifiable {
    var id: UUID
    var name: String
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double?
    var fatGrams: Double?

    init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        proteinGrams: Double,
        carbsGrams: Double? = nil,
        fatGrams: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
    }

    // Create FoodEntry from saved meal
    func toFoodEntry(for date: Date) -> FoodEntry {
        FoodEntry(
            dayDate: date,
            name: name,
            calories: calories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            isSavedMeal: true
        )
    }

    // Default saved meals for Rob
    static let defaults: [SavedMeal] = [
        SavedMeal(name: "Clear Whey Shake", calories: 90, proteinGrams: 20),
        SavedMeal(name: "Casein Shake", calories: 120, proteinGrams: 24),
        SavedMeal(name: "Meal Prep Bowl", calories: 450, proteinGrams: 40, carbsGrams: 45, fatGrams: 12)
    ]
}

// Manager for saved meals
class SavedMealsManager {
    private static let userDefaultsKey = "savedMeals"

    static func load() -> [SavedMeal] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let meals = try? JSONDecoder().decode([SavedMeal].self, from: data) else {
            // Return defaults if nothing saved
            return SavedMeal.defaults
        }
        return meals
    }

    static func save(_ meals: [SavedMeal]) {
        if let encoded = try? JSONEncoder().encode(meals) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    static func add(_ meal: SavedMeal) {
        var meals = load()
        meals.append(meal)
        save(meals)
    }

    static func delete(_ meal: SavedMeal) {
        var meals = load()
        meals.removeAll { $0.id == meal.id }
        save(meals)
    }
}
