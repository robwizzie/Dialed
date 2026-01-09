//
//  DayLog.swift
//  Dialed
//
//  Daily log entry - main data model
//

import Foundation
import SwiftData

@Model
final class DayLog {
    // Identity
    var date: Date  // Normalized to start of day

    // Score (final vs. provisional)
    var dailyScoreFinal: Int?  // Set when day is finalized
    var dailyScoreProvisional: Int  // Live calculated score

    // Workout data
    var workoutTag: String?  // WorkoutTag rawValue
    var workoutScore: Int?  // 0-5 quality rating
    var workoutDetectedFromHealth: Bool
    var workoutDurationMinutes: Int?
    var workoutCaloriesBurned: Int?

    // Mile data
    var mileCompleted: Bool
    var mileScore: Int?  // 0-5 quality rating
    var mileDistance: Double?  // Actual distance run
    var mileTimeSeconds: Int?

    // Sleep data (from RingConn/HealthKit)
    var sleepScore: Int?  // 0-5 calculated from metrics
    var sleepDurationMinutes: Int?
    var sleepDeepMinutes: Int?
    var sleepREMMinutes: Int?
    var sleepLightMinutes: Int?
    var sleepAwakeMinutes: Int?
    var sleepEfficiency: Double?  // 0-1
    var sleepHRV: Double?  // Heart rate variability
    var sleepRestingHR: Double?  // Resting heart rate

    // Nutrition
    var proteinGrams: Double
    var caloriesConsumed: Double
    var carbsGrams: Double?
    var fatGrams: Double?

    // Hydration
    var waterOz: Double

    // Activity metrics (from Apple Watch)
    var steps: Int?
    var activeEnergyBurned: Int?
    var exerciseMinutes: Int?

    // Finalization
    var isFinalized: Bool
    var finalizedAt: Date?

    // Relationships
    @Relationship(deleteRule: .cascade) var foodEntries: [FoodEntry]?
    @Relationship(deleteRule: .cascade) var workoutLog: WorkoutLog?
    @Relationship(deleteRule: .cascade) var checklistItems: [ChecklistItem]?

    init(date: Date) {
        // Normalize to start of day
        let calendar = Calendar.current
        self.date = calendar.startOfDay(for: date)

        // Initialize with zeros
        self.dailyScoreProvisional = 0
        self.workoutDetectedFromHealth = false
        self.mileCompleted = false
        self.proteinGrams = 0
        self.caloriesConsumed = 0
        self.waterOz = 0
        self.isFinalized = false

        // Create default checklist items
        var items = Constants.ChecklistType.allCases.map { type in
            ChecklistItem(type: type, dayDate: self.date)
        }

        // Add custom checklist items from saved templates
        if let data = UserDefaults.standard.data(forKey: "routineTaskTemplates"),
           let templates = try? JSONDecoder().decode([RoutineTaskTemplate].self, from: data) {
            let customItems = templates.map { template in
                ChecklistItem(
                    customTitle: template.title,
                    customDescription: template.description,
                    customPoints: template.points,
                    scheduledTime: template.scheduledTime,
                    dayDate: self.date
                )
            }
            items.append(contentsOf: customItems)
        }

        // Sort by scheduled time
        self.checklistItems = items.sorted { item1, item2 in
            let hour1 = item1.scheduledTime.hour ?? 0
            let minute1 = item1.scheduledTime.minute ?? 0
            let hour2 = item2.scheduledTime.hour ?? 0
            let minute2 = item2.scheduledTime.minute ?? 0
            return (hour1 * 60 + minute1) < (hour2 * 60 + minute2)
        }
    }

    // Calculate total protein from food entries
    func calculateTotalProtein() -> Double {
        return (foodEntries ?? []).reduce(0) { $0 + $1.proteinGrams }
    }

    // Calculate total calories from food entries
    func calculateTotalCalories() -> Double {
        return (foodEntries ?? []).reduce(0) { $0 + $1.calories }
    }

    // Update nutrition totals from food entries
    func updateNutritionTotals() {
        self.proteinGrams = calculateTotalProtein()
        self.caloriesConsumed = calculateTotalCalories()
    }
}
