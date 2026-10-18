//
//  WeightDataSource.swift
//  Dialed
//
//  One place that knows where scale readings come from: Apple Health body
//  mass (most smart scales write here), the Fitbit weight log (Aria, or any
//  scale synced to a Google/Fitbit account) and manual weigh-ins. Returns a
//  single de-duplicated list for the Home and Challenge screens.
//

import Foundation
import SwiftData

@MainActor
enum WeightDataSource {

    static func readings(context: ModelContext, since start: Date) async -> [WeightReading] {
        async let healthKit = healthKitReadings(since: start)
        let fitbit = await fitbitReadings(since: start)
        let manual = manualReadings(context: context, since: start)
        return WeightChallengeEngine.merge([await healthKit, fitbit, manual])
    }

    private static func healthKitReadings(since start: Date) async -> [WeightReading] {
        let samples = (try? await HealthKitManager.shared.fetchWeightReadings(since: start)) ?? []
        return samples.map { WeightReading(date: $0.date, pounds: $0.value, source: .healthKit) }
    }

    /// Fitbit caps a weight-log range at 31 days, so read the most recent
    /// 30 days of the window.
    private static func fitbitReadings(since start: Date) async -> [WeightReading] {
        guard FitbitTokenStore.isConnected else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = max(calendar.startOfDay(for: start), calendar.date(byAdding: .day, value: -30, to: today) ?? today)
        guard let resp = try? await FitbitAPIClient.shared.weightLogs(from: from, to: today) else { return [] }
        return resp.weight.compactMap { entry in
            guard let date = FitbitAPIClient.parseDay(entry.date, time: entry.time)
                    ?? FitbitAPIClient.parseDay(entry.date) else { return nil }
            return WeightReading(date: date, pounds: entry.weight * 2.20462, source: .fitbit)
        }
    }

    private static func manualReadings(context: ModelContext, since start: Date) -> [WeightReading] {
        let desc = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.timestamp >= start },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return ((try? context.fetch(desc)) ?? []).map {
            WeightReading(date: $0.timestamp, pounds: $0.pounds, source: .manual)
        }
    }
}
