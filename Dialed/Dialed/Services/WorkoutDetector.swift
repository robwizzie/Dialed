//
//  WorkoutDetector.swift
//  Dialed
//
//  Finds today's workouts on their own: Apple Fitness / Apple Watch (and
//  anything else that writes workouts to Apple Health) plus Google Health
//  (Pixel Watch, Fitbit). Home shows them, and the logger starts with
//  their times and distances filled in, so all that's left is the sets.
//

import Foundation
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

struct DetectedWorkout: Identifiable, Equatable {
    enum Kind: String { case strength, run, walk, bike, other }

    var id: String
    var title: String
    var kind: Kind
    var start: Date
    var end: Date
    var miles: Double?
    var calories: Int?
    var source: String

    var minutes: Double { end.timeIntervalSince(start) / 60 }

    var isCardio: Bool { kind == .run || kind == .walk || kind == .bike }

    /// "6:15–6:45 PM"
    var timeText: String {
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(start.formatted(f))–\(end.formatted(f))"
    }
}

enum WorkoutDetector {

    /// Watches and phones log the same session twice; keep one per overlap
    /// (Apple Health first, it's listed first), longest wins otherwise.
    static func merge(_ lists: [DetectedWorkout]...) -> [DetectedWorkout] {
        var out: [DetectedWorkout] = []
        for w in lists.flatMap({ $0 }) where w.minutes >= 3 {
            let overlaps = out.firstIndex { o in
                o.kind == w.kind && o.start < w.end && w.start < o.end
                    && min(o.end, w.end).timeIntervalSince(max(o.start, w.start)) >= 0.5 * min(o.minutes, w.minutes) * 60
            }
            if let i = overlaps {
                if out[i].miles == nil { out[i].miles = w.miles }
                if out[i].calories == nil { out[i].calories = w.calories }
            } else {
                out.append(w)
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Google's exercise type names ("WEIGHTLIFTING", "RUNNING", "TREADMILL"…).
    static func kind(google type: String?) -> DetectedWorkout.Kind {
        let t = (type ?? "").lowercased()
        if t.contains("run") || t.contains("treadmill") || t.contains("jog") { return .run }
        if t.contains("walk") || t.contains("hik") { return .walk }
        if t.contains("bik") || t.contains("cycl") || t.contains("spin") { return .bike }
        if t.contains("weight") || t.contains("strength") || t.contains("lift") || t.contains("gym")
            || t.contains("crossfit") || t.contains("circuit") || t.contains("interval") { return .strength }
        return .other
    }

    static func title(for kind: DetectedWorkout.Kind) -> String {
        switch kind {
        case .strength: return "Strength"
        case .run:      return "Run"
        case .walk:     return "Walk"
        case .bike:     return "Bike"
        case .other:    return "Workout"
        }
    }

    // MARK: - Fetch

    /// Everything recorded on `day` from Apple Health and Google Health.
    @MainActor
    static func workouts(on day: Date, context: ModelContext) async -> [DetectedWorkout] {
        async let apple = appleHealth(on: day)
        let google = GoogleHealthSyncService.isConnected
            ? await GoogleHealthSyncService(modelContext: context).exercises(on: day)
            : []
        return merge(await apple, google)
    }

    /// Time already accounted for by a workout from any app, padded a few
    /// minutes each side — nothing in here becomes a suggested activity.
    /// Unlike `workouts(on:)` this keeps short workouts and ones that
    /// started the evening before.
    @MainActor
    static func busyIntervals(on day: Date, context: ModelContext) async -> [DateInterval] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day
        var raw: [DateInterval] = []
        #if canImport(HealthKit)
        raw += (try? await HealthKitManager.shared.fetchWorkoutIntervals(from: start, to: end)) ?? []
        #endif
        if GoogleHealthSyncService.isConnected {
            let google = GoogleHealthSyncService(modelContext: context)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            for w in await google.exercises(on: day) + google.exercises(on: yesterday) where w.end > start && w.start < end {
                raw.append(DateInterval(start: w.start, end: max(w.start, w.end)))
            }
        }
        return ActivityAccounting.busyIntervals(raw)
    }

    private static func appleHealth(on day: Date) async -> [DetectedWorkout] {
        #if canImport(HealthKit)
        guard let workouts = try? await HealthKitManager.shared.fetchWorkouts(for: day) else { return [] }
        return workouts.map { w in
            let kind: DetectedWorkout.Kind
            switch w.workoutType {
            case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining,
                 .highIntensityIntervalTraining, .crossTraining, .mixedCardio:
                kind = .strength
            case .running:  kind = .run
            case .walking, .hiking: kind = .walk
            case .cycling:  kind = .bike
            default:        kind = .other
            }
            return DetectedWorkout(
                id: w.id.uuidString, title: kind == .other ? w.workoutTypeName : title(for: kind), kind: kind,
                start: w.startDate, end: w.endDate,
                miles: w.distance.map { $0 / 1609.344 }.flatMap { $0 > 0.01 ? $0 : nil },
                calories: w.caloriesBurned, source: w.sourceName ?? "Apple Health")
        }
        #else
        return []
        #endif
    }
}

extension GoogleHealthSyncService {
    /// Exercise sessions that started on `day` (Pixel Watch, Fitbit).
    func exercises(on day: Date) async -> [DetectedWorkout] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day
        guard let points = try? await GoogleHealthAPI.shared.list(
            "exercise",
            filter: "exercise.interval.start_time >= \"\(GHTime.rfc3339(start))\""
        ) else { return [] }
        return points.compactMap { p -> DetectedWorkout? in
            guard let e = p.exercise,
                  let s = GHTime.parse(e.interval?.startTime),
                  let f = GHTime.parse(e.interval?.endTime), s < end else { return nil }
            let kind = WorkoutDetector.kind(google: e.exerciseType ?? e.displayName)
            return DetectedWorkout(
                id: p.name ?? "google-\(s.timeIntervalSince1970)",
                title: e.displayName ?? WorkoutDetector.title(for: kind), kind: kind,
                start: s, end: f,
                miles: e.metricsSummary?.distanceMillimeters.map { $0 / 1_609_344 }.flatMap { $0 > 0.01 ? $0 : nil },
                calories: e.metricsSummary?.caloriesKcal.map { Int($0) },
                source: "Google Health")
        }
    }
}
