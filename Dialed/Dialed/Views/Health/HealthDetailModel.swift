//
//  HealthDetailModel.swift
//  Dialed
//
//  Loads one day (and the two weeks before it) for the Health tab's Body,
//  Sleep and Nutrition pages: Apple Health, the Pixel Watch data synced
//  from Google Health, and what you log in Dialed.
//

import Foundation
import SwiftData
import HealthKit
#if canImport(Combine)
import Combine
#endif

@MainActor
final class HealthDetailModel: ObservableObject {
    typealias DayValue = HealthInsights.DayValue

    @Published var day: Date = Calendar.current.startOfDay(for: Date())
    @Published private(set) var isLoading = false
    /// The day whose numbers are on screen; nil until the first load lands.
    /// Differs from `day` while a new day loads.
    @Published private(set) var loadedDay: Date?

    // MARK: Body
    @Published private(set) var restingHR: [DayValue] = []
    @Published private(set) var hrv: [DayValue] = []
    @Published private(set) var respiratory: [DayValue] = []
    @Published private(set) var spO2: [DayValue] = []
    @Published private(set) var skinTemp: [DayValue] = []
    @Published private(set) var weight: [DayValue] = []
    @Published private(set) var dailySteps: [DayValue] = []
    @Published private(set) var stepsHourly: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var intakeHourly: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var burnHourly: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var readiness: Int?
    @Published private(set) var stress: HealthInsights.Stress?
    @Published private(set) var illness: HealthInsights.IllnessCheck?

    // MARK: Sleep
    @Published private(set) var nights: [HealthInsights.Night] = []
    @Published private(set) var hypnogram: [HealthKitManager.SleepSegment] = []
    @Published private(set) var sleepPlan: HealthInsights.SleepPlan?

    // MARK: Nutrition
    @Published private(set) var nutrition = HealthInsights.NutritionDay(
        calories: 0, calorieTarget: 0, protein: 0, proteinTarget: 0, waterOz: 0, waterTargetOz: 0, fiber: nil)
    @Published private(set) var carbs: Double = 0
    @Published private(set) var fat: Double = 0
    @Published private(set) var sugar: Double?
    @Published private(set) var sodiumMg: Double?
    @Published private(set) var caffeineMg: Double?
    @Published private(set) var proteinHistory: [DayValue] = []
    @Published private(set) var meals: [Meal] = []

    struct Meal: Identifiable, Equatable {
        let id = UUID()
        let time: Date
        let name: String
        let calories: Double
    }

    private let health = HealthKitManager.shared
    private let calendar = Calendar.current

    // MARK: - Derived

    /// First load, or stepping to a day that hasn't loaded yet — the pages
    /// redact rather than flash zeros and "no data" (refreshes don't).
    var isShowingStaleDay: Bool { loadedDay != day }

    var isToday: Bool { calendar.isDateInToday(day) }
    var canGoForward: Bool { !isToday }
    var canGoBack: Bool {
        guard let limit = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: Date())) else { return false }
        return day > limit
    }

    /// Last night = the night you woke up on `day`.
    var lastNight: HealthInsights.Night? {
        nights.first { calendar.isDate($0.wakeDay, inSameDayAs: day) }
    }

    func value(on series: [DayValue]) -> Double? {
        series.last { $0.date <= day }?.value
    }

    func shift(_ days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        day = min(calendar.startOfDay(for: Date()), next)
        followsToday = isToday
    }

    /// True while you're looking at today (not a day you stepped back to).
    private var followsToday = true

    /// After midnight, a page that was showing "today" moves to the new day
    /// instead of staying on yesterday.
    func rollToToday() {
        let today = calendar.startOfDay(for: Date())
        if followsToday && day != today { day = today }
    }

    // MARK: - Load

    /// A load asked for while one is running; it runs once that finishes.
    private var reloadQueued = false

    /// Loads `day`. Calls that land mid-load (data-change bursts, a day
    /// step) fold into one more pass instead of running side by side.
    func load(context: ModelContext) async {
        if isLoading {
            reloadQueued = true
            return
        }
        repeat {
            reloadQueued = false
            await performLoad(context: context)
        } while reloadQueued
    }

    private func performLoad(context: ModelContext) async {
        isLoading = true
        defer { isLoading = false }

        let day = self.day
        let windowStart = calendar.date(byAdding: .day, value: -14, to: day) ?? day
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let settings = UserSettings.load()

        // Apple Health reads, in parallel (and alongside loadSignals).
        async let hkSteps = try? health.fetchDailySums(.stepCount, unit: .count(), days: 14)
        async let hkStepsHour = try? health.fetchHourlySums(.stepCount, unit: .count(), on: day)
        async let hkActiveHour = try? health.fetchHourlySums(.activeEnergyBurned, unit: .kilocalorie(), on: day)
        async let hkBasalHour = try? health.fetchHourlySums(.basalEnergyBurned, unit: .kilocalorie(), on: day)
        async let hkIntakeHour = try? health.fetchHourlySums(.dietaryEnergyConsumed, unit: .kilocalorie(), on: day)
        async let hkProteinDays = try? health.fetchDailySums(.dietaryProtein, unit: .gram(), days: 14)
        async let hkWaterHour = try? health.fetchHourlySums(.dietaryWater, unit: .fluidOunceUS(), on: day)
        async let hkCarbs = try? health.fetchHourlySums(.dietaryCarbohydrates, unit: .gram(), on: day)
        async let hkFat = try? health.fetchHourlySums(.dietaryFatTotal, unit: .gram(), on: day)
        async let hkFiber = try? health.fetchHourlySums(.dietaryFiber, unit: .gram(), on: day)
        async let hkSugar = try? health.fetchHourlySums(.dietarySugar, unit: .gram(), on: day)
        async let hkSodium = try? health.fetchHourlySums(.dietarySodium, unit: .gramUnit(with: .milli), on: day)
        async let hkCaffeine = try? health.fetchHourlySums(.dietaryCaffeine, unit: .gramUnit(with: .milli), on: day)

        await loadSignals(context: context)
        let weights = await WeightDataSource.readings(context: context, since: windowStart)

        // Local data.
        let logs = fetch(context, FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < dayEnd }))
        let events = fetch(context, FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate >= windowStart && $0.logicalDate < dayEnd }))
        let foods = fetch(context, FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.dayDate >= day && $0.dayDate < dayEnd }))

        weight = Dictionary(grouping: weights) { calendar.startOfDay(for: $0.date) }
            .map { DayValue(date: $0.key, value: $0.value.last!.pounds) }
            .sorted { $0.date < $1.date }

        let stepsByDay = await hkSteps ?? [:]
        dailySteps = (0..<14).compactMap { back -> DayValue? in
            guard let d = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: Date())) else { return nil }
            let log = logs.first { calendar.isDate($0.date, inSameDayAs: d) }
            return DayValue(date: d, value: max(stepsByDay[d] ?? 0, Double(log?.steps ?? 0)))
        }.reversed()
        stepsHourly = await hkStepsHour ?? Array(repeating: 0, count: 24)

        // Calories in by hour: Apple Health, plus meals logged in Dialed.
        var intake = await hkIntakeHour ?? Array(repeating: 0, count: 24)
        let dayMeals = events.filter { $0.kindRaw == ContextEvent.Kind.meal.rawValue && calendar.isDate($0.logicalDate, inSameDayAs: day) }
        if intake.reduce(0, +) == 0 {
            for m in dayMeals { intake[calendar.component(.hour, from: m.timestamp)] += m.value ?? 0 }
            for f in foods { intake[calendar.component(.hour, from: f.timestamp)] += f.calories }
        }
        intakeHourly = intake

        // Calories out by hour: resting + active from the watch, else an estimate.
        let currentWeight = weight.last?.value ?? settings.currentWeight
        let active = await hkActiveHour ?? Array(repeating: 0, count: 24)
        let basal = await hkBasalHour ?? Array(repeating: 0, count: 24)
        let basalTotal = basal.reduce(0, +)
        burnHourly = (0..<24).map { h in
            (basalTotal > 0 ? basal[h] : currentWeight * 12 / 24) + active[h]
        }

        // ---- Nutrition
        let log = logs.first { calendar.isDate($0.date, inSameDayAs: day) }
        let loggedCalories = (log?.caloriesConsumed ?? 0) + dayMeals.reduce(0) { $0 + ($1.value ?? 0) }
        let loggedProtein = (log?.proteinGrams ?? 0) + dayMeals.reduce(0) { $0 + ($1.secondaryValue ?? 0) }
        let proteinDays = await hkProteinDays ?? [:]
        let waterEvents = events.filter { $0.kindRaw == ContextEvent.Kind.water.rawValue && calendar.isDate($0.logicalDate, inSameDayAs: day) }
        let deviceWater = max((await hkWaterHour ?? []).reduce(0, +), log?.waterOz ?? 0)
        let calorieTarget = CalorieTarget.current(settings: settings, weight: currentWeight)

        func total(_ hours: [Double]?) -> Double? {
            let t = (hours ?? []).reduce(0, +)
            return t > 0 ? t : nil
        }
        nutrition = HealthInsights.NutritionDay(
            calories: max(loggedCalories, intake.reduce(0, +)),
            calorieTarget: calorieTarget,
            protein: max(loggedProtein, proteinDays[day] ?? 0),
            proteinTarget: settings.proteinTargetGrams,
            waterOz: deviceWater + waterEvents.reduce(0) { $0 + ($1.value ?? 0) },
            waterTargetOz: settings.waterTargetOz,
            fiber: total(await hkFiber))
        carbs = max(foods.reduce(0) { $0 + ($1.carbsGrams ?? 0) }, total(await hkCarbs) ?? 0)
        fat = max(foods.reduce(0) { $0 + ($1.fatGrams ?? 0) }, total(await hkFat) ?? 0)
        sugar = total(await hkSugar)
        sodiumMg = total(await hkSodium)
        let caffeineEvents = events
            .filter { $0.kindRaw == ContextEvent.Kind.caffeine.rawValue && calendar.isDate($0.logicalDate, inSameDayAs: day) }
            .reduce(0) { $0 + ($1.value ?? 0) }
        let caffeine = max(total(await hkCaffeine) ?? 0, caffeineEvents)
        caffeineMg = caffeine > 0 ? caffeine : nil

        proteinHistory = (0..<7).compactMap { back -> DayValue? in
            guard let d = calendar.date(byAdding: .day, value: -back, to: day) else { return nil }
            let l = logs.first { calendar.isDate($0.date, inSameDayAs: d) }
            let m = events.filter { $0.kindRaw == ContextEvent.Kind.meal.rawValue && calendar.isDate($0.logicalDate, inSameDayAs: d) }
                .reduce(0) { $0 + ($1.secondaryValue ?? 0) }
            return DayValue(date: d, value: max((l?.proteinGrams ?? 0) + m, proteinDays[d] ?? 0))
        }.reversed()

        meals = (dayMeals.map { Meal(time: $0.timestamp, name: Self.mealName($0), calories: $0.value ?? 0) }
                 + foods.map { Meal(time: $0.timestamp, name: $0.name, calories: $0.calories) })
            .sorted { $0.time < $1.time }
        loadedDay = day
    }

    /// Overnight vitals, sleep, and the scores built from them (readiness,
    /// stress, illness watch, tonight's plan) for `day`. All Home's Body
    /// Check card needs, without the nutrition and hourly reads.
    func loadSignals(context: ModelContext) async {
        let day = self.day
        let windowStart = calendar.date(byAdding: .day, value: -14, to: day) ?? day
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day

        async let hkRHR = try? health.fetchSamples(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: windowStart, to: dayEnd)
        async let hkHRV = try? health.fetchSamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: windowStart, to: dayEnd)
        async let hkResp = try? health.fetchSamples(.respiratoryRate, unit: .count().unitDivided(by: .minute()), from: windowStart, to: dayEnd)
        async let hkO2 = try? health.fetchSamples(.oxygenSaturation, unit: .percent(), from: windowStart, to: dayEnd)
        async let hkWrist = try? health.fetchSamples(.appleSleepingWristTemperature, unit: .degreeCelsius(), from: windowStart, to: dayEnd)

        let snapshots = fetch(context, FetchDescriptor<BiometricSnapshot>(
            predicate: #Predicate { $0.timestamp >= windowStart && $0.timestamp < dayEnd },
            sortBy: [SortDescriptor(\.timestamp)]))
        let sessions = fetch(context, FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.logicalDate >= windowStart && $0.logicalDate < dayEnd },
            sortBy: [SortDescriptor(\.logicalDate)]))

        // ---- Body: watch (Google) first, Apple Health to fill gaps.
        restingHR = merge(daily(snapshots) { $0.restingHeartRate }, averaged(await hkRHR ?? []))
        // Not merged: the watch reports RMSSD, Apple Health SDNN, and SDNN
        // runs much higher for the same person — a baseline mixing the two
        // makes a normal night look like a crash. Apple Health only when
        // the watch has no HRV at all.
        let watchHRV = daily(snapshots) { $0.hrv }
        hrv = watchHRV.isEmpty ? averaged(await hkHRV ?? []) : watchHRV
        respiratory = merge(daily(snapshots) { $0.breathingRate }, averaged(await hkResp ?? []))
        spO2 = merge(daily(snapshots) { $0.spO2 }, averaged((await hkO2 ?? []).map { HealthKitManager.QuantityReading(date: $0.date, value: $0.value * 100) }))
        let wrist = averaged(await hkWrist ?? [])
        let wristMean = HealthInsights.mean(wrist.map(\.value))
        skinTemp = merge(daily(snapshots) { $0.skinTemperatureDelta },
                         wrist.map { DayValue(date: $0.date, value: $0.value - (wristMean ?? $0.value)) })

        // ---- Sleep: every session that woke you that day, joined into one
        // night (a split night is still one night).
        nights = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.logicalDate) }
            .compactMap { _, group in
                HealthInsights.combine(group.map { s in
                    HealthInsights.Night(
                        wakeDay: calendar.startOfDay(for: s.logicalDate), bedtime: s.startTime, wakeTime: s.endTime,
                        inBedMinutes: s.inBedMinutes, asleepMinutes: s.asleepMinutes,
                        deepMinutes: s.deepMinutes, remMinutes: s.remMinutes, lightMinutes: s.lightMinutes,
                        awakeMinutes: s.awakeMinutes, awakenings: s.awakeningCount, vendorScore: s.vendorSleepScore,
                        segments: s.stageTimeline)
                })
            }
            .sorted { $0.wakeDay < $1.wakeDay }
        if let night = lastNight {
            hypnogram = night.segments.isEmpty
                ? await health.fetchSleepStages(from: night.bedtime.addingTimeInterval(-3600),
                                                to: night.wakeTime.addingTimeInterval(3600))
                : night.segments
        } else {
            hypnogram = []
        }

        // ---- Scores, each against the days before `day`.
        let prior = { (series: [DayValue]) in series.filter { $0.date < day }.suffix(14).map(\.value) }
        readiness = HealthInsights.readiness(
            hrv: value(on: hrv), hrvBaseline: prior(hrv),
            restingHR: value(on: restingHR), rhrBaseline: prior(restingHR),
            sleepHours: lastNight?.hours)
        stress = HealthInsights.stress(
            hrv: value(on: hrv), hrvBaseline: prior(hrv),
            restingHR: value(on: restingHR), rhrBaseline: prior(restingHR),
            sleepHours: lastNight?.hours,
            respiratory: value(on: respiratory), respBaseline: prior(respiratory))
        // Illness watch only reads this day's overnight values — a stale
        // reading from days ago shouldn't raise (or clear) a flag.
        illness = HealthInsights.illnessCheck(
            restingHR: exact(restingHR), rhrBaseline: prior(restingHR),
            hrv: exact(hrv), hrvBaseline: prior(hrv),
            respiratory: exact(respiratory), respBaseline: prior(respiratory),
            skinTemp: exact(skinTemp), skinTempBaseline: prior(skinTemp),
            spO2: exact(spO2), spO2Baseline: prior(spO2),
            sleepHours: lastNight?.hours)
        sleepPlan = HealthInsights.sleepPlan(history: nights.filter { $0.wakeDay <= day })
    }

    private func exact(_ series: [DayValue]) -> Double? {
        series.first { calendar.isDate($0.date, inSameDayAs: day) }?.value
    }

    // MARK: - Helpers

    private func fetch<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    /// One value per day from synced watch snapshots (latest reading that day).
    private func daily(_ snapshots: [BiometricSnapshot], _ value: (BiometricSnapshot) -> Double?) -> [DayValue] {
        var byDay: [Date: Double] = [:]
        for s in snapshots {
            if let v = value(s) { byDay[calendar.startOfDay(for: s.timestamp)] = v }
        }
        return byDay.map { DayValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }

    /// Daily averages of raw Apple Health samples.
    private func averaged(_ samples: [HealthKitManager.QuantityReading]) -> [DayValue] {
        Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
            .map { DayValue(date: $0.key, value: $0.value.map(\.value).reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }

    /// Primary series, with days it's missing filled from the fallback.
    private func merge(_ primary: [DayValue], _ fallback: [DayValue]) -> [DayValue] {
        var byDay = Dictionary(fallback.map { ($0.date, $0.value) }, uniquingKeysWith: { a, _ in a })
        for p in primary { byDay[p.date] = p.value }
        return byDay.map { DayValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }

    private static func mealName(_ event: ContextEvent) -> String { event.mealName }
}
