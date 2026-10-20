//
//  MetabolismLoader.swift
//  Dialed
//
//  Gathers what MetabolismEstimator needs: three weeks of food (logged in
//  Dialed or from Health, whichever is larger), Apple Health active
//  energy, trend weight, and your age, sex, height and body fat (Health
//  first, then what you entered in Settings → Profile).
//

import Foundation
import SwiftData
import HealthKit

@MainActor
enum MetabolismLoader {

    /// Manual fallbacks when Apple Health doesn't share them.
    nonisolated static let birthDateKey = "profile.birthDate"
    nonisolated static let sexKey = "profile.sex"

    struct Report {
        var result: MetabolismEstimator.Result
        var profile: MetabolismEstimator.Profile
    }

    static func load(context: ModelContext, now: Date = Date(), windowDays: Int = 21) async -> Report {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let health = HealthKitManager.shared

        // Trend weight, with a little lead-in so the window's first day has one.
        let since = calendar.date(byAdding: .day, value: -(windowDays + 14), to: today) ?? today
        let readings = await WeightDataSource.readings(context: context, since: since)
        let series = WeightChallengeEngine.dailySeries(readings)
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: today) ?? today
        let inWindow = series.filter { $0.day >= windowStart && $0.day < today }
        let first = inWindow.first, last = inWindow.last

        // Food and active energy per day, between the first and last trend days.
        async let hkFood = try? health.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: windowDays + 2)
        async let hkActive = try? health.fetchDailySums(.activeEnergyBurned, unit: .kilocalorie(), days: windowDays + 2)
        let foodByDay = await hkFood ?? [:]
        let activeByDay = await hkActive ?? [:]
        var days: [MetabolismEstimator.Day] = []
        if let first, let last {
            var d = first.day
            while d <= last.day {
                let logged = FoodLog.entries(on: d, context: context).reduce(0) { $0 + $1.calories }
                let eaten = max(logged, foodByDay[d] ?? 0)
                days.append(.init(date: d, eaten: eaten > 0 ? eaten : nil, active: activeByDay[d]))
                d = calendar.date(byAdding: .day, value: 1, to: d) ?? last.day.addingTimeInterval(86_400)
            }
        }

        // Profile.
        let traits = health.profileCharacteristics()
        let manualBirth = UserDefaults.standard.double(forKey: birthDateKey)
        let birth = traits.birthDate ?? (manualBirth > 0 ? Date(timeIntervalSince1970: manualBirth) : nil)
        let sexRaw = traits.sex ?? UserDefaults.standard.string(forKey: sexKey)
        let age = birth.map { now.timeIntervalSince($0) / (365.25 * 86_400) }
        let height = (try? await health.fetchLatest(.height, unit: .inch(), withinDays: 3_650))?.value
            ?? UserSettings.load().height
        let bodyFat = (try? await health.fetchLatest(.bodyFatPercentage, unit: .percent(), withinDays: 30))?.value
        let weight = series.last?.trend ?? UserSettings.load().currentWeight

        let profile = MetabolismEstimator.Profile(
            age: age, sex: sexRaw.flatMap(MetabolismEstimator.Sex.init(rawValue:)),
            heightInches: height, weightLbs: weight, bodyFat: bodyFat)
        let result = MetabolismEstimator.estimate(profile: profile, days: days,
                                                  trendStart: first?.trend, trendEnd: last?.trend)
        return Report(result: result, profile: profile)
    }
}
