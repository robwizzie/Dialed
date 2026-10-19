//
//  WeightDataSource.swift
//  Dialed
//
//  One place that knows where scale readings come from: Apple Health body
//  mass (most smart scales write here), Google Health weight (any scale
//  synced to your Google account) and manual weigh-ins. Returns a
//  single de-duplicated list for the Home and Challenge screens.
//

import Foundation
import SwiftData

@MainActor
enum WeightDataSource {

    static func readings(context: ModelContext, since start: Date) async -> [WeightReading] {
        async let healthKit = healthKitReadings(since: start)
        let google = await googleHealthReadings(context: context, since: start)
        let manual = manualReadings(context: context, since: start)
        return WeightChallengeEngine.merge([await healthKit, google, manual])
    }

    private static func healthKitReadings(since start: Date) async -> [WeightReading] {
        let samples = (try? await HealthKitManager.shared.fetchWeightReadings(since: start)) ?? []
        return samples.map { WeightReading(date: $0.date, pounds: $0.value, source: .healthKit) }
    }

    /// Weigh-ins from any scale synced to the Google account.
    private static func googleHealthReadings(context: ModelContext, since start: Date) async -> [WeightReading] {
        guard GoogleHealthSyncService.isConnected else { return [] }
        return await GoogleHealthSyncService(modelContext: context).weights(since: start)
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
