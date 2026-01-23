//
//  LogViewModel.swift
//  Dialed
//
//  Manages Log screen state, date selection, and food/workout data
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
class LogViewModel: ObservableObject {
    // Published state
    @Published var selectedDate: Date
    @Published var dayLog: DayLog?
    @Published var foodEntries: [FoodEntry] = []
    @Published var workoutLog: WorkoutLog?
    @Published var settings: UserSettings
    @Published var isLoading = false
    
    // Model context
    private let modelContext: ModelContext
    
    // Computed properties
    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    var formattedDate: String {
        if isToday {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }
    
    var totalCalories: Double {
        foodEntries.reduce(0) { $0 + $1.calories }
    }
    
    var totalProtein: Double {
        foodEntries.reduce(0) { $0 + $1.proteinGrams }
    }
    
    var calorieProgress: Double {
        guard let target = settings.calorieTarget, target > 0 else { return 0 }
        return min(totalCalories / target, 1.5)
    }
    
    var proteinProgress: Double {
        guard settings.proteinTargetGrams > 0 else { return 0 }
        return min(totalProtein / settings.proteinTargetGrams, 1.5)
    }
    
    // Workout summary
    var hasWorkout: Bool {
        workoutLog != nil || (dayLog?.workoutTag != nil)
    }
    
    var workoutSummary: (tag: String?, score: Int?, duration: Int?, calories: Int?, exerciseCount: Int) {
        if let workout = workoutLog {
            return (
                tag: workout.tag,
                score: workout.workoutScore,
                duration: workout.durationMinutes,
                calories: workout.caloriesBurned,
                exerciseCount: workout.exercises?.count ?? 0
            )
        }
        return (
            tag: dayLog?.workoutTag,
            score: dayLog?.workoutScore,
            duration: dayLog?.workoutDurationMinutes,
            calories: dayLog?.workoutCaloriesBurned,
            exerciseCount: 0
        )
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.selectedDate = Calendar.current.startOfDay(for: Date())
        self.settings = UserSettings.load()
        
        loadDataForSelectedDate()
    }
    
    // MARK: - Data Loading
    
    func loadDataForSelectedDate() {
        isLoading = true
        
        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        
        // Fetch DayLog
        let dayLogDescriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date == targetDate }
        )
        
        if let existingLog = try? modelContext.fetch(dayLogDescriptor).first {
            dayLog = existingLog
            workoutLog = existingLog.workoutLog
            foodEntries = existingLog.foodEntries ?? []
        } else if isToday {
            // Create new DayLog for today if doesn't exist
            let newLog = DayLog(date: targetDate)
            modelContext.insert(newLog)
            try? modelContext.save()
            dayLog = newLog
            workoutLog = nil
            foodEntries = []
        } else {
            dayLog = nil
            workoutLog = nil
            foodEntries = []
        }
        
        // Also fetch workout log directly in case the relationship is not established
        let workoutDescriptor = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate { $0.dayDate == targetDate }
        )
        if let existingWorkout = try? modelContext.fetch(workoutDescriptor).first {
            workoutLog = existingWorkout
        }
        
        // Fetch food entries directly
        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.dayDate == targetDate },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let entries = try? modelContext.fetch(foodDescriptor) {
            foodEntries = entries
        }
        
        isLoading = false
    }
    
    func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        loadDataForSelectedDate()
    }
    
    func goToToday() {
        selectDate(Date())
    }
    
    func goToPreviousDay() {
        if let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
            selectDate(previousDay)
        }
    }
    
    func goToNextDay() {
        if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
            // Don't go past today
            if nextDay <= Date() {
                selectDate(nextDay)
            }
        }
    }
    
    // MARK: - Food Entry Actions
    
    func addFoodEntry(name: String, calories: Double, protein: Double, carbs: Double?, fat: Double?, saveAsMeal: Bool) {
        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        
        let entry = FoodEntry(
            dayDate: targetDate,
            name: name,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat
        )
        
        modelContext.insert(entry)
        
        // Ensure we have a DayLog
        if dayLog == nil {
            let newLog = DayLog(date: targetDate)
            modelContext.insert(newLog)
            dayLog = newLog
        }
        
        // Update nutrition totals
        dayLog?.updateNutritionTotals()
        
        try? modelContext.save()
        
        // Save as meal if requested
        if saveAsMeal {
            let savedMeal = SavedMeal(
                name: name,
                calories: calories,
                proteinGrams: protein,
                carbsGrams: carbs,
                fatGrams: fat
            )
            SavedMealsManager.add(savedMeal)
        }
        
        loadDataForSelectedDate()
    }
    
    func addSavedMeal(_ meal: SavedMeal) {
        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        let entry = meal.toFoodEntry(for: targetDate)
        
        modelContext.insert(entry)
        
        // Ensure we have a DayLog
        if dayLog == nil {
            let newLog = DayLog(date: targetDate)
            modelContext.insert(newLog)
            dayLog = newLog
        }
        
        dayLog?.updateNutritionTotals()
        try? modelContext.save()
        
        loadDataForSelectedDate()
    }
    
    func deleteFoodEntry(_ entry: FoodEntry) {
        modelContext.delete(entry)
        dayLog?.updateNutritionTotals()
        try? modelContext.save()
        
        loadDataForSelectedDate()
    }
    
    func updateFoodEntry(_ entry: FoodEntry, name: String, calories: Double, protein: Double, carbs: Double?, fat: Double?) {
        entry.name = name
        entry.calories = calories
        entry.proteinGrams = protein
        entry.carbsGrams = carbs
        entry.fatGrams = fat
        
        dayLog?.updateNutritionTotals()
        try? modelContext.save()
        
        loadDataForSelectedDate()
    }
    
    // MARK: - Get DayLog for Workout Sheet
    
    func getOrCreateDayLog() -> DayLog {
        if let existing = dayLog {
            return existing
        }
        
        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        let newLog = DayLog(date: targetDate)
        modelContext.insert(newLog)
        try? modelContext.save()
        dayLog = newLog
        return newLog
    }
    
    func refreshData() {
        loadDataForSelectedDate()
    }
}
