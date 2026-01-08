//
//  HealthDataSyncService.swift
//  Dialed
//
//  Syncs HealthKit data to DayLog and calculates automated scores
//

import Foundation
import SwiftData
import HealthKit

@MainActor
class HealthDataSyncService: ObservableObject {
    private let healthKitManager = HealthKitManager.shared
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?

    /// Sync all HealthKit data for a specific date
    func syncHealthData(for date: Date, dayLog: DayLog) async {
        guard healthKitManager.checkAuthorizationStatus() else {
            print("HealthKit not authorized, skipping sync")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Sync in parallel for speed
            async let sleepData = try healthKitManager.fetchSleepData(for: date)
            async let workouts = try healthKitManager.fetchWorkouts(for: date)
            async let mileCheck = try healthKitManager.checkMileCompleted(for: date)
            async let steps = try healthKitManager.fetchSteps(for: date)
            async let activeEnergy = try healthKitManager.fetchActiveEnergy(for: date)
            async let exerciseMinutes = try healthKitManager.fetchExerciseMinutes(for: date)
            async let water = try healthKitManager.fetchWaterIntake(for: date)

            // Update DayLog with sleep data
            if var sleep = try await sleepData {
                // Enrich with HRV and resting HR data
                if let sleepStart = sleep.sleepStart, let sleepEnd = sleep.sleepEnd {
                    sleep.hrv = try? await healthKitManager.fetchAverageHRV(start: sleepStart, end: sleepEnd)
                }
                sleep.restingHR = try? await healthKitManager.fetchRestingHeartRate(for: date)
                
                updateSleepData(dayLog: dayLog, sleepData: sleep)
            }

            // Update workout data
            let workoutList = try await workouts
            if let primaryWorkout = workoutList.first {
                updateWorkoutData(dayLog: dayLog, workout: primaryWorkout)
            }

            // Update mile data
            let (mileCompleted, mileDistance, mileTime) = try await mileCheck
            if mileCompleted {
                dayLog.mileCompleted = true
                dayLog.mileDistance = mileDistance
                dayLog.mileTimeSeconds = mileTime
            }

            // Update activity metrics
            dayLog.steps = try await steps
            dayLog.activeEnergyBurned = try await activeEnergy
            dayLog.exerciseMinutes = try await exerciseMinutes

            // Update water (combine with manual entries)
            if let healthWater = try await water {
                // If user hasn't manually logged water, use HealthKit data
                if dayLog.waterOz == 0 {
                    dayLog.waterOz = healthWater
                }
            }

            lastSyncDate = Date()

        } catch {
            syncError = error
            print("HealthKit sync error: \(error.localizedDescription)")
        }
    }

    private func updateSleepData(dayLog: DayLog, sleepData: HealthKitManager.SleepData) {
        // Store raw sleep metrics
        dayLog.sleepDurationMinutes = sleepData.totalSleepMinutes
        dayLog.sleepDeepMinutes = sleepData.deepSleepMinutes
        dayLog.sleepREMMinutes = sleepData.remSleepMinutes
        dayLog.sleepLightMinutes = sleepData.lightSleepMinutes
        dayLog.sleepAwakeMinutes = sleepData.awakeDurationMinutes
        dayLog.sleepEfficiency = sleepData.timeInBedMinutes.map { bed in
            Double(sleepData.totalSleepMinutes) / Double(bed)
        }
        dayLog.sleepHRV = sleepData.hrv
        dayLog.sleepRestingHR = sleepData.restingHR

        // Calculate automated sleep score
        let sleepScore = ScoringEngine.calculateSleepScore(
            totalSleepMinutes: sleepData.totalSleepMinutes,
            deepSleepMinutes: sleepData.deepSleepMinutes,
            remSleepMinutes: sleepData.remSleepMinutes,
            awakeDurationMinutes: sleepData.awakeDurationMinutes,
            timeInBedMinutes: sleepData.timeInBedMinutes,
            hrv: sleepData.hrv,
            restingHR: sleepData.restingHR
        )

        dayLog.sleepScore = sleepScore
    }

    private func updateWorkoutData(dayLog: DayLog, workout: HealthKitManager.WorkoutData) {
        dayLog.workoutDetectedFromHealth = true
        dayLog.workoutDurationMinutes = workout.durationMinutes
        dayLog.workoutCaloriesBurned = workout.caloriesBurned

        // Auto-tag workout type based on HKWorkoutActivityType
        if dayLog.workoutTag == nil {
            dayLog.workoutTag = mapWorkoutTypeToTag(workout.workoutType).rawValue
        }

        // If no workout score yet, we'll prompt user to rate it
        // For now, leave workoutScore nil so UI knows to ask for rating
    }

    private func mapWorkoutTypeToTag(_ workoutType: HKWorkoutActivityType) -> Constants.WorkoutTag {
        // Map HealthKit workout types to our custom tags
        // This is a best guess - user can override
        switch workoutType {
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return .push  // Default guess, user should override
        case .running, .walking:
            return .armsCore  // If they're running, might be arms+core day
        case .cycling:
            return .legs
        default:
            return .upperPump  // Generic default
        }
    }

    /// Quick sync for Today view (fetch only essentials)
    func quickSync(for date: Date, dayLog: DayLog) async {
        guard healthKitManager.checkAuthorizationStatus() else { return }

        do {
            // Just fetch today's critical metrics
            async let water = try healthKitManager.fetchWaterIntake(for: date)
            async let steps = try healthKitManager.fetchSteps(for: date)

            if let healthWater = try await water, dayLog.waterOz == 0 {
                dayLog.waterOz = healthWater
            }

            dayLog.steps = try await steps

        } catch {
            print("Quick sync error: \(error.localizedDescription)")
        }
    }

    /// Sync sleep data (typically called in the morning)
    func syncSleepOnly(for date: Date, dayLog: DayLog) async {
        guard healthKitManager.checkAuthorizationStatus() else { return }

        do {
            if let sleepData = try await healthKitManager.fetchSleepData(for: date) {
                updateSleepData(dayLog: dayLog, sleepData: sleepData)
            }
        } catch {
            print("Sleep sync error: \(error.localizedDescription)")
        }
    }
}
