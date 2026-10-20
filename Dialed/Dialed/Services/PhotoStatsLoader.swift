//
//  PhotoStatsLoader.swift
//  Dialed
//
//  The readings PhotoStats matches against each progress photo: your
//  weigh-ins as a trend series and smart-scale body fat from Apple Health,
//  covering the photos' whole span.
//

import Foundation
import SwiftData
import HealthKit

struct PhotoStatsData {
    var series: [WeightChallengeEngine.DailyWeight] = []
    var bodyFat: [PhotoStats.Reading] = []

    func stats(for entry: ProgressPhotoEntry) -> PhotoStats.Stats {
        PhotoStats.stats(on: entry.date, photoWeight: entry.weightLbs, series: series, bodyFat: bodyFat)
    }

    @MainActor
    static func load(for entries: [ProgressPhotoEntry], context: ModelContext) async -> PhotoStatsData {
        guard let first = entries.map(\.date).min() else { return PhotoStatsData() }
        // A couple of weeks before the first photo, so its trend has history.
        let since = Calendar.current.date(byAdding: .day, value: -21, to: first) ?? first
        let readings = await WeightDataSource.readings(context: context, since: since)
        let fat = (try? await HealthKitManager.shared.fetchSamples(.bodyFatPercentage, unit: .percent(), from: since)) ?? []
        return PhotoStatsData(series: WeightChallengeEngine.dailySeries(readings),
                              bodyFat: fat.map { PhotoStats.Reading(date: $0.date, value: $0.value) })
    }
}
