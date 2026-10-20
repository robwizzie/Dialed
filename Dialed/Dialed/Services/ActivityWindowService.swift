//
//  ActivityWindowService.swift
//  Dialed
//
//  Everything that says you were moving during a heart-rate stretch, from
//  15 minutes before to 15 after: heart rate (Apple Health and Google),
//  steps, active calories, distance, flights climbed and any workout that
//  overlaps. Each source has its own time limit so a slow one only leaves
//  its own row empty.
//

import Foundation
import SwiftData
import HealthKit

@MainActor
enum ActivityWindowService {

    struct Evidence: Equatable {
        var start: Date
        var end: Date
        var heartRate: [ActiveBouts.Sample] = []
        var heartSources: [String] = []
        var steps: Double?
        var activeCalories: Double?
        var miles: Double?
        var flights: Double?
        var workouts: [DetectedWorkout] = []
    }

    static let padding: TimeInterval = 15 * 60

    static func load(_ bout: ActiveBouts.Bout, context: ModelContext) async -> Evidence {
        let start = bout.start.addingTimeInterval(-padding)
        let end = bout.end.addingTimeInterval(padding)
        let health = HealthKitManager.shared
        let limit = 8.0
        let bpm = HKUnit.count().unitDivided(by: .minute())

        async let hkHeart = DayLoadKit.withTimeout(seconds: limit) {
            (try? await health.fetchSamples(.heartRate, unit: bpm, from: start, to: end)) ?? []
        }
        async let google = DayLoadKit.withTimeout(seconds: limit) { () -> [ActiveBouts.Sample] in
            guard GoogleHealthSyncService.isConnected else { return [] }
            return await GoogleHealthSyncService(modelContext: context).heartRate(from: start, to: end)
        }
        async let steps = sum(.stepCount, .count(), bout, limit)
        async let energy = sum(.activeEnergyBurned, .kilocalorie(), bout, limit)
        async let distance = sum(.distanceWalkingRunning, .mile(), bout, limit)
        async let flights = sum(.flightsClimbed, .count(), bout, limit)
        async let workouts = DayLoadKit.withTimeout(seconds: limit) {
            await WorkoutDetector.workouts(on: bout.start, context: context)
        }

        var e = Evidence(start: start, end: end)
        let apple = (await hkHeart ?? []).map { ActiveBouts.Sample(date: $0.date, bpm: $0.value) }
        let fromGoogle = await google ?? []
        if !apple.isEmpty { e.heartSources.append("Apple Health") }
        if !fromGoogle.isEmpty { e.heartSources.append("Google Health") }
        e.heartRate = (apple + fromGoogle).sorted { $0.date < $1.date }
        e.steps = await steps
        e.activeCalories = await energy
        e.miles = await distance
        e.flights = await flights
        e.workouts = (await workouts ?? []).filter { $0.start < end && $0.end > start }
        return e
    }

    /// Total of a quantity over the stretch itself (not the padding).
    private static func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ bout: ActiveBouts.Bout,
                            _ limit: Double) async -> Double? {
        let samples = await DayLoadKit.withTimeout(seconds: limit) {
            (try? await HealthKitManager.shared.fetchSamples(id, unit: unit, from: bout.start, to: bout.end)) ?? []
        }
        guard let samples, !samples.isEmpty else { return nil }
        let total = samples.reduce(0) { $0 + $1.value }
        return total > 0 ? total : nil
    }
}
