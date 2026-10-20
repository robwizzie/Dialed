//
//  HealthKitManager.swift
//  Dialed
//
//  HealthKit integration for automated data fetching
//  Pulls data from: RingConn (sleep), Apple Watch (workouts, activity), Smart water bottle
//

import Foundation
import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    nonisolated static let shared = HealthKitManager()

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

        if let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distanceType)
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

        // Home body callouts + fuel card
        let extra: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .respiratoryRate,
            .oxygenSaturation,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            // Health tab: macros, micros, temperature
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryFiber,
            .dietarySugar,
            .dietarySodium,
            .dietaryCaffeine,
            .basalEnergyBurned,
            .appleSleepingWristTemperature
        ]
        for identifier in extra {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        return types
    }()

    /// Food and water Dialed mirrors into Apple Health (see HealthWriteBack).
    nonisolated static let intakeIdentifiers: Set<HKQuantityTypeIdentifier> = [
        .dietaryWater, .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal
    ]

    /// Types we ask to write — meals and water logged in Dialed.
    nonisolated static let typesToShare: Set<HKSampleType> = {
        var types: Set<HKSampleType> = Set(intakeIdentifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        // Intimacy logged in Dialed → Health's Sexual Activity.
        types.insert(HKCategoryType(.sexualActivity))
        return types
    }()

    nonisolated private init() {}

    /// Date-window predicate for a quantity type. For food and water it also
    /// leaves out samples Dialed wrote itself: those mirror meals and water
    /// we already count from SwiftData, so reading them back would double them.
    nonisolated static func samplePredicate(
        _ identifier: HKQuantityTypeIdentifier,
        start: Date?,
        end: Date?,
        options: HKQueryOptions
    ) -> NSPredicate {
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: options)
        guard intakeIdentifiers.contains(identifier) else { return window }
        let ours = HKQuery.predicateForObjects(from: [HKSource.default()])
        let notOurs = NSCompoundPredicate(notPredicateWithSubpredicate: ours)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [window, notOurs])
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        print("🏥 [HealthKit] Requesting authorization...")
        print("🏥 [HealthKit] Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ [HealthKit] Health data not available on this device")
            throw HealthKitError.notAvailable
        }

        print("🏥 [HealthKit] Requesting access to \(typesToRead.count) data types:")
        for (index, type) in typesToRead.enumerated() {
            print("  \(index + 1). \(type)")
        }
        
        do {
            // First check current status before requesting
            print("🔍 [HealthKit] Current authorization status BEFORE request:")
            _ = checkAuthorizationStatus()
            
            try await healthStore.requestAuthorization(toShare: Self.typesToShare, read: typesToRead)
            print("✅ [HealthKit] Authorization request completed")
            
            // Wait for iOS to update the authorization state
            print("⏳ [HealthKit] Waiting 2 seconds for permissions to propagate...")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Check status after delay
            print("🔍 [HealthKit] Authorization status AFTER request (with 2s delay):")
            let actualStatus = checkAuthorizationStatus()
            
            await MainActor.run {
                self.isAuthorized = actualStatus
            }
            
            print("🏥 [HealthKit] Final result: \(actualStatus ? "AUTHORIZED ✅" : "NOT AUTHORIZED ❌")")
        } catch {
            print("❌ [HealthKit] Authorization request failed: \(error.localizedDescription)")
            await MainActor.run {
                self.authorizationError = error
            }
            throw error
        }
    }

    /// True when iOS still has an unanswered permission prompt for any
    /// type we read — e.g. after an update added heart rate / SpO₂ / food.
    func needsAuthorizationPrompt() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: Self.typesToShare, read: typesToRead) { status, _ in
                continuation.resume(returning: status == .shouldRequest)
            }
        }
    }

    nonisolated func checkAuthorizationStatus() -> Bool {
        print("🔍 [HealthKit] NOTE: For privacy, HealthKit hides READ authorization status")
        print("🔍 [HealthKit] Status API may show DENIED even when access is granted")
        print("🔍 [HealthKit] The only way to verify is to try reading data")
        
        // For READ permissions, authorizationStatus is unreliable
        // Apple intentionally returns .sharingDenied to protect privacy
        // We'll assume authorized if user completed the authorization flow
        
        // Still check the status for logging purposes
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            print("⚠️ [HealthKit] Could not get sleep type")
            return false
        }

        let sleepStatus = healthStore.authorizationStatus(for: sleepType)
        
        print("🏥 [HealthKit] Sleep Analysis status: \(sleepStatus.rawValue)")
        print("💡 [HealthKit] If status shows DENIED but Settings shows ON, this is normal!")
        print("💡 [HealthKit] We'll try reading data to verify actual access")
        
        // Return true if not explicitly notDetermined
        // This allows the app to attempt data reading
        return sleepStatus != .notDetermined
    }
    
    // New function to actually verify we can read data
    func verifyDataAccess() async -> Bool {
        print("🧪 [HealthKit] Testing actual data access by attempting to read...")
        
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            print("❌ [HealthKit] Could not get sleep type for verification")
            return false
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            end: Date(),
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("❌ [HealthKit] Data read test failed: \(error.localizedDescription)")
                    print("💡 [HealthKit] This means access is actually DENIED")
                    continuation.resume(returning: false)
                } else {
                    print("✅ [HealthKit] Data read test succeeded!")
                    print("✅ [HealthKit] Access is GRANTED (found \(samples?.count ?? 0) sleep samples)")
                    continuation.resume(returning: true)
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    nonisolated func getAuthorizationStatusDescription() -> String {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return "Unable to check"
        }
        
        let status = healthStore.authorizationStatus(for: sleepType)
        
        switch status {
        case .notDetermined:
            return "not_determined"
        case .sharingDenied:
            return "denied"
        case .sharingAuthorized:
            return "authorized"
        @unknown default:
            return "unknown"
        }
    }

    // MARK: - Workout Detection

    struct WorkoutData {
        var id: UUID  // HealthKit workout UUID for linking
        var workoutType: HKWorkoutActivityType
        var startDate: Date
        var endDate: Date
        var durationMinutes: Int
        var caloriesBurned: Int?
        var distance: Double?  // meters
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var sourceName: String?  // e.g. "Apple Watch", "Fitness App"
        
        /// Formatted display name for the workout type
        var workoutTypeName: String {
            switch workoutType {
            case .traditionalStrengthTraining: return "Strength Training"
            case .functionalStrengthTraining: return "Functional Training"
            case .running: return "Running"
            case .walking: return "Walking"
            case .cycling: return "Cycling"
            case .swimming: return "Swimming"
            case .yoga: return "Yoga"
            case .pilates: return "Pilates"
            case .hiking: return "Hiking"
            case .coreTraining: return "Core Training"
            case .highIntensityIntervalTraining: return "HIIT"
            case .crossTraining: return "Cross Training"
            case .elliptical: return "Elliptical"
            case .rowing: return "Rowing"
            case .stairClimbing: return "Stair Climbing"
            case .jumpRope: return "Jump Rope"
            case .flexibility: return "Flexibility"
            case .mixedCardio: return "Mixed Cardio"
            case .cooldown: return "Cooldown"
            case .dance: return "Dance"
            case .mindAndBody: return "Mind & Body"
            case .other: return "Other"
            default: return "Workout"
            }
        }
        
        /// SF Symbol name for the workout type
        var workoutTypeIcon: String {
            switch workoutType {
            case .traditionalStrengthTraining, .functionalStrengthTraining:
                return "dumbbell.fill"
            case .running:
                return "figure.run"
            case .walking:
                return "figure.walk"
            case .cycling:
                return "bicycle"
            case .swimming:
                return "figure.pool.swim"
            case .yoga, .pilates, .flexibility, .mindAndBody:
                return "figure.yoga"
            case .hiking:
                return "figure.hiking"
            case .coreTraining:
                return "figure.core.training"
            case .highIntensityIntervalTraining:
                return "flame.fill"
            case .crossTraining:
                return "figure.cross.training"
            case .elliptical:
                return "figure.elliptical"
            case .rowing:
                return "figure.rower"
            case .stairClimbing:
                return "figure.stairs"
            case .jumpRope:
                return "figure.jumprope"
            case .dance:
                return "figure.dance"
            default:
                return "figure.strengthtraining.traditional"
            }
        }
    }

    /// Fetch workouts for a specific date
    /// On-foot workouts (walks, runs, hikes) between two dates, totalled
    /// per day: miles, how many workouts, and whether any was a run. Used
    /// by the daily mile so a logged walk or run counts even when the
    /// phone's own distance missed it.
    func fetchFootWorkoutMiles(from start: Date, to end: Date) async -> [Date: (miles: Double, count: Int, ran: Bool)] {
        let calendar = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let onFoot: Set<HKWorkoutActivityType> = [.walking, .running, .hiking, .wheelchairWalkPace, .wheelchairRunPace]
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
        var out: [Date: (miles: Double, count: Int, ran: Bool)] = [:]
        for w in workouts where onFoot.contains(w.workoutActivityType) {
            let miles = w.totalDistance?.doubleValue(for: .mile()) ?? 0
            guard miles > 0 else { continue }
            let day = calendar.startOfDay(for: w.startDate)
            var entry = out[day] ?? (0, 0, false)
            entry.miles += miles
            entry.count += 1
            entry.ran = entry.ran || w.workoutActivityType == .running || w.workoutActivityType == .wheelchairRunPace
            out[day] = entry
        }
        return out
    }

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
                        id: workout.uuid,
                        workoutType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        durationMinutes: Int(workout.duration / 60.0),
                        caloriesBurned: workout.totalEnergyBurned.map { Int($0.doubleValue(for: .kilocalorie())) },
                        distance: workout.totalDistance.map { $0.doubleValue(for: .meter()) },
                        averageHeartRate: nil,  // Would need separate query
                        maxHeartRate: nil,
                        sourceName: workout.sourceRevision.source.name
                    )
                }

                continuation.resume(returning: workoutData)
            }

            healthStore.execute(query)
        }
    }
    
    /// Fetch a specific workout by UUID
    func fetchWorkout(byID id: String) async throws -> WorkoutData? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        
        let predicate = HKQuery.predicateForObject(with: uuid)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let workout = (samples as? [HKWorkout])?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let workoutData = WorkoutData(
                    id: workout.uuid,
                    workoutType: workout.workoutActivityType,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    durationMinutes: Int(workout.duration / 60.0),
                    caloriesBurned: workout.totalEnergyBurned.map { Int($0.doubleValue(for: .kilocalorie())) },
                    distance: workout.totalDistance.map { $0.doubleValue(for: .meter()) },
                    averageHeartRate: nil,
                    maxHeartRate: nil,
                    sourceName: workout.sourceRevision.source.name
                )
                
                continuation.resume(returning: workoutData)
            }
            
            healthStore.execute(query)
        }
    }

    /// Fetch the HKWorkout object by ID (private helper)
    private func fetchWorkoutHK(byID workoutID: UUID) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForObject(with: workoutID)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let workout = (samples as? [HKWorkout])?.first
                continuation.resume(returning: workout)
            }
            
            healthStore.execute(query)
        }
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

    // MARK: - Series & latest readings (Home / Challenge)

    struct QuantityReading: Equatable {
        let date: Date
        let value: Double
    }

    /// Every sample of a quantity type in a window, oldest first.
    func fetchSamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date = Date()
    ) async throws -> [QuantityReading] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = Self.samplePredicate(identifier, start: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let readings = (samples as? [HKQuantitySample] ?? []).map {
                    QuantityReading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: readings)
            }
            healthStore.execute(query)
        }
    }

    /// Most recent sample of a quantity type within the last `days` days.
    func fetchLatest(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        withinDays days: Int = 2
    ) async throws -> QuantityReading? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let reading = (samples?.first as? HKQuantitySample).map {
                    QuantityReading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: reading)
            }
            healthStore.execute(query)
        }
    }

    /// Per-day cumulative totals for the last `days` days (today included),
    /// keyed by start of day. Days with no data are omitted.
    func fetchDailySums(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int
    ) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [:] }
        let predicate = Self.samplePredicate(identifier, start: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                var totals: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: unit) {
                        totals[calendar.startOfDay(for: stats.startDate)] = sum
                    }
                }
                continuation.resume(returning: totals)
            }
            healthStore.execute(query)
        }
    }

    /// Hourly totals for one day (24 slots, midnight first).
    func fetchHourlySums(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        on day: Date
    ) async throws -> [Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return Array(repeating: 0, count: 24) }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return Array(repeating: 0, count: 24) }
        let predicate = Self.samplePredicate(identifier, start: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(hour: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                var hours = Array(repeating: 0.0, count: 24)
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let hour = calendar.component(.hour, from: stats.startDate)
                    if (0..<24).contains(hour), let sum = stats.sumQuantity()?.doubleValue(for: unit) {
                        hours[hour] += sum
                    }
                }
                continuation.resume(returning: hours)
            }
            healthStore.execute(query)
        }
    }

    enum SleepStage: String, Codable { case awake, rem, light, deep }

    struct SleepSegment: Equatable, Codable {
        let start: Date
        let end: Date
        let stage: SleepStage
    }

    /// Stage-by-stage sleep (for the hypnogram) between two times, from any
    /// app that writes sleep stages to Apple Health. Empty when none.
    func fetchSleepStages(from start: Date, to end: Date) async -> [SleepSegment] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let segments: [SleepSegment] = (samples as? [HKCategorySample] ?? []).compactMap { sample in
                    let stage: SleepStage
                    switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    case .awake?:      stage = .awake
                    case .asleepREM?:  stage = .rem
                    case .asleepDeep?: stage = .deep
                    case .asleepCore?, .asleepUnspecified?: stage = .light
                    default:           return nil   // in bed
                    }
                    return SleepSegment(start: sample.startDate, end: sample.endDate, stage: stage)
                }
                continuation.resume(returning: segments)
            }
            healthStore.execute(query)
        }
    }

    /// Names of the apps that wrote samples of a type since `start`
    /// (e.g. ["WaterH"] for dietary water). Empty when none or no access.
    func sourceNames(_ identifier: HKQuantityTypeIdentifier, since start: Date) async -> [String] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSourceQuery(sampleType: type, samplePredicate: predicate) { _, sources, _ in
                // Dialed's own write-back isn't a device feeding us data.
                let own = HKSource.default().bundleIdentifier
                let names = (sources ?? []).filter { $0.bundleIdentifier != own }.map(\.name).sorted()
                continuation.resume(returning: names)
            }
            healthStore.execute(query)
        }
    }

    /// Body-mass readings in lbs, oldest first.
    func fetchWeightReadings(since start: Date) async throws -> [QuantityReading] {
        try await fetchSamples(.bodyMass, unit: .pound(), from: start)
    }

    // MARK: - Helper Methods

    private func fetchDailyTotal(for quantityType: HKQuantityType, date: Date, unit: HKUnit) async throws -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let identifier = HKQuantityTypeIdentifier(rawValue: quantityType.identifier)
        let predicate = Self.samplePredicate(identifier, start: startOfDay, end: endOfDay, options: .strictStartDate)

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
