//
//  TodayViewModel.swift
//  Dialed
//
//  Manages Today screen state, HealthKit sync, and live scoring
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
class TodayViewModel: ObservableObject {
    // Published state
    @Published var dayLog: DayLog
    @Published var provisionalScore: Int = 0
    @Published var isSyncing = false

    // Services
    private let healthSyncService = HealthDataSyncService()
    
    // Settings (exposed for view access)
    let settings: UserSettings

    // Model context (injected)
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.settings = UserSettings.load()

        // Get or create today's DayLog
        let today = Calendar.current.startOfDay(for: Date())
        let fetchDescriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date == today }
        )

        if let existingLog = try? modelContext.fetch(fetchDescriptor).first {
            self.dayLog = existingLog
        } else {
            let newLog = DayLog(date: today)
            modelContext.insert(newLog)
            try? modelContext.save()
            self.dayLog = newLog
        }

        // Calculate initial score
        updateProvisionalScore()
    }

    // MARK: - Data Refresh

    func refreshData() async {
        isSyncing = true

        // Sync HealthKit data
        await healthSyncService.syncHealthData(for: dayLog.date, dayLog: dayLog)

        // Update provisional score
        updateProvisionalScore()

        // Save changes
        try? modelContext.save()

        isSyncing = false
    }

    func quickRefresh() async {
        // Just sync essentials (water, steps) without full sync
        await healthSyncService.quickSync(for: dayLog.date, dayLog: dayLog)
        updateProvisionalScore()
        try? modelContext.save()
    }

    // MARK: - Checklist Actions

    func toggleChecklistItem(_ item: ChecklistItem) {
        switch item.checklistStatus {
        case .open:
            item.markDone()
        case .done:
            item.markSkipped()
        case .skipped:
            item.reset()
        }

        updateProvisionalScore()
        try? modelContext.save()
    }

    // MARK: - Score Calculation

    private func updateProvisionalScore() {
        // Update nutrition totals from food entries
        dayLog.updateNutritionTotals()

        // Calculate score
        provisionalScore = ScoringEngine.calculateProvisionalScore(
            from: dayLog,
            settings: settings
        )

        // Update day log's provisional score
        dayLog.dailyScoreProvisional = provisionalScore
    }

    // MARK: - Computed Properties

    var scoreGrade: String {
        AppColors.scoreGrade(for: provisionalScore)
    }

    var scoreColor: Color {
        AppColors.scoreColor(for: provisionalScore)
    }

    var currentStreak: Int {
        // TODO: Implement streak calculation
        // For now, return placeholder
        return 0
    }

    // Nutrition
    var proteinProgress: Double {
        dayLog.proteinGrams / settings.proteinTargetGrams
    }

    var waterProgress: Double {
        dayLog.waterOz / settings.waterTargetOz
    }

    var caloriesProgress: Double? {
        guard let target = settings.calorieTarget, target > 0 else { return nil }
        return dayLog.caloriesConsumed / target
    }

    // Checklist
    var checklistItems: [ChecklistItem] {
        dayLog.checklistItems ?? []
    }

    var checklistCompletionPercentage: Double {
        let items = checklistItems
        guard !items.isEmpty else { return 0 }
        let completed = items.filter { $0.checklistStatus == .done }.count
        return Double(completed) / Double(items.count)
    }

    // Sleep summary for tile
    var sleepSummary: (score: Int?, duration: Int?, deepSleep: Int?, efficiency: Double?) {
        (
            score: dayLog.sleepScore,
            duration: dayLog.sleepDurationMinutes,
            deepSleep: dayLog.sleepDeepMinutes,
            efficiency: dayLog.sleepEfficiency
        )
    }

    // Workout summary for tile
    var workoutSummary: (detected: Bool, tag: String?, score: Int?, duration: Int?, calories: Int?) {
        (
            detected: dayLog.workoutDetectedFromHealth || dayLog.workoutTag != nil,
            tag: dayLog.workoutTag,
            score: dayLog.workoutScore,
            duration: dayLog.workoutDurationMinutes,
            calories: dayLog.workoutCaloriesBurned
        )
    }

    // Activity metrics
    var activityMetrics: (steps: Int?, activeEnergy: Int?) {
        (
            steps: dayLog.steps,
            activeEnergy: dayLog.activeEnergyBurned
        )
    }
}
