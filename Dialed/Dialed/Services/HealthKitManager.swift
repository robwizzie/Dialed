//
//  HealthKitManager.swift
//  Dialed
//
//  HealthKit integration for automated data fetching
//  Pulls data from: RingConn (sleep), Apple Watch (workouts, activity), Smart water bottle
//

import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var authorizationError: Error?

    // Health data types we need to read
    private let typesToRead: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []

        // Sleep analysis
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        // Activity metrics
        if let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepsType)
        }

        if let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergyType)
        }

        if let exerciseMinutesType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseMinutesType)
        }

        // Workouts
        types.insert(HKObjectType.workoutType())

        // Water intake
        if let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(waterType)
        }

        // Heart metrics
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrvType)
        }

        if let restingHRType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHRType)
        }

        // Optional: Body metrics
        if let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weightType)
        }

        if let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(bodyFatType)
        }

        return types
    }()

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            await MainActor.run {
                self.isAuthorized = true
            }
        } catch {
            await MainActor.run {
                self.authorizationError = error
            }
            throw error
        }
    }

    func checkAuthorizationStatus() -> Bool {
        // Check if at least the critical types are authorized
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return false
        }

        let status = healthStore.authorizationStatus(for: sleepType)
        return status == .sharingAuthorized
    }

    // MARK: - Sleep Data Fetching

    struct SleepData {
        var totalSleepMinutes: Int
        var deepSleepMinutes: Int?
        var remSleepMinutes: Int?
        var lightSleepMinutes: Int?
        var awakeDurationMinutes: Int?
        var timeInBedMinutes: Int?
        var hrv: Double?
        var restingHR: Double?
        var sleepStart: Date?
        var sleepEnd: Date?
    }

    /// Fetch sleep data for a specific date
    func fetchSleepData(for date: Date) async throws -> SleepData? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.dataTypeNotAvailable
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        // Sleep typically spans from previous evening to morning
        // Check from 8 PM previous day to 2 PM current day
        guard let searchStart = calendar.date(byAdding: .hour, value: -4, to: startOfDay),
              let searchEnd = calendar.date(byAdding: .hour, value: 14, to: startOfDay) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: searchStart, end: searchEnd, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample], !sleepSamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Calculate sleep metrics from samples
                var totalAsleepMinutes = 0
                var deepMinutes = 0
                var remMinutes = 0
                var lightMinutes = 0
                var awakeMinutes = 0
                var inBedMinutes = 0
                var sleepStart: Date?
                var sleepEnd: Date?

                for sample in sleepSamples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0  // minutes

                    if sleepStart == nil || sample.startDate < sleepStart! {
                        sleepStart = sample.startDate
                    }
                    if sleepEnd == nil || sample.endDate > sleepEnd! {
                        sleepEnd = sample.endDate
                    }

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                         HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        totalAsleepMinutes += Int(duration)
                        lightMinutes += Int(duration)  // Default to light if unspecified

                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        totalAsleepMinutes += Int(duration)
                        deepMinutes += Int(duration)

                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        totalAsleepMinutes += Int(duration)
                        remMinutes += Int(duration)

                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awakeMinutes += Int(duration)

                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        inBedMinutes += Int(duration)

                    default:
                        break
                    }
                }

                // Calculate total time in bed
                if let start = sleepStart, let end = sleepEnd {
                    inBedMinutes = max(inBedMinutes, Int(end.timeIntervalSince(start) / 60.0))
                }

                // Fetch HRV and resting HR for the sleep period
                Task {
                    let hrv = try? await self.fetchAverageHRV(start: sleepStart, end: sleepEnd)
                    let restingHR = try? await self.fetchRestingHeartRate(for: date)

                    let sleepData = SleepData(
                        totalSleepMinutes: totalAsleepMinutes,
                        deepSleepMinutes: deepMinutes > 0 ? deepMinutes : nil,
                        remSleepMinutes: remMinutes > 0 ? remMinutes : nil,
                        lightSleepMinutes: lightMinutes > 0 ? lightMinutes : nil,
                        awakeDurationMinutes: awakeMinutes > 0 ? awakeMinutes : nil,
                        timeInBedMinutes: inBedMinutes > 0 ? inBedMinutes : nil,
                        hrv: hrv,
                        restingHR: restingHR,
                        sleepStart: sleepStart,
                        sleepEnd: sleepEnd
                    )

                    continuation.resume(returning: sleepData)
                }
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Workout Detection

    struct WorkoutData {
        var workoutType: HKWorkoutActivityType
        var startDate: Date
        var endDate: Date
        var durationMinutes: Int
        var caloriesBurned: Int?
        var distance: Double?  // meters
        var averageHeartRate: Double?
        var maxHeartRate: Double?
    }

    /// Fetch workouts for a specific date
    func fetchWorkouts(for date: Date) async throws -> [WorkoutData] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let workoutData = workouts.map { workout in
                    WorkoutData(
                        workoutType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        durationMinutes: Int(workout.duration / 60.0),
                        caloriesBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()).map(Int.init),
                        distance: workout.totalDistance?.doubleValue(for: .meter()),
                        averageHeartRate: nil,  // Would need separate query
                        maxHeartRate: nil
                    )
                }

                continuation.resume(returning: workoutData)
            }

            healthStore.execute(query)
        }
    }

    /// Check if mile was completed (any running workout ≥ 1 mile)
    func checkMileCompleted(for date: Date) async throws -> (completed: Bool, distance: Double?, timeSeconds: Int?) {
        let workouts = try await fetchWorkouts(for: date)

        // Filter for running/walking workouts
        let runningWorkouts = workouts.filter { workout in
            workout.workoutType == .running ||
            workout.workoutType == .walking ||
            workout.workoutType == .hiking
        }

        // Check if any workout had ≥ 1 mile (1609 meters)
        if let longestRun = runningWorkouts.max(by: { ($0.distance ?? 0) < ($1.distance ?? 0) }),
           let distance = longestRun.distance,
           distance >= 1609 {
            let miles = distance / 1609.34
            return (true, miles, longestRun.durationMinutes * 60)
        }

        return (false, nil, nil)
    }

    // MARK: - Activity Metrics

    /// Fetch step count for a date
    func fetchSteps(for date: Date) async throws -> Int? {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }

        return try await fetchDailyTotal(for: stepsType, date: date, unit: .count()).map(Int.init)
    }

    /// Fetch active energy burned for a date
    func fetchActiveEnergy(for date: Date) async throws -> Int? {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        return try await fetchDailyTotal(for: energyType, date: date, unit: .kilocalorie()).map(Int.init)
    }

    /// Fetch exercise minutes for a date
    func fetchExerciseMinutes(for date: Date) async throws -> Int? {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            return nil
        }

        return try await fetchDailyTotal(for: exerciseType, date: date, unit: .minute()).map(Int.init)
    }

    // MARK: - Water Intake

    /// Fetch water intake for a date (in ounces)
    func fetchWaterIntake(for date: Date) async throws -> Double? {
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            return nil
        }

        // Water is typically in liters, convert to oz
        let liters = try await fetchDailyTotal(for: waterType, date: date, unit: .liter())
        return liters.map { $0 * 33.814 }  // Convert liters to oz
    }

    // MARK: - Heart Metrics

    private func fetchAverageHRV(start: Date?, end: Date?) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let start = start,
              let end = end else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrvType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let average = statistics?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: average)
            }

            healthStore.execute(query)
        }
    }

    private func fetchRestingHeartRate(for date: Date) async throws -> Double? {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return nil
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: restingHRType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let average = statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: average)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Helper Methods

    private func fetchDailyTotal(for quantityType: HKQuantityType, date: Date, unit: HKUnit) async throws -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let total = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: total)
            }

            healthStore.execute(query)
        }
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case dataTypeNotAvailable
    case authorizationFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .dataTypeNotAvailable:
            return "The requested health data type is not available"
        case .authorizationFailed:
            return "Failed to authorize HealthKit access"
        }
    }
}
