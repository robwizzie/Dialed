//
//  FunActivityService.swift
//  Dialed
//
//  Today's fun activity: heart-rate bouts found by ActiveBouts (from
//  Apple Health and Google Health / Pixel Watch), workouts your watch
//  recorded as something other than the gym (pickleball, golf…), and what
//  you've named. Named ones are saved as workout events (subtype "fun"),
//  so they show on the Timeline with minutes and calories.
//

import Foundation
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
enum FunActivityService {

    static let subtype = "fun"
    private static let dismissedKey = "fun.dismissedBouts"

    struct Day {
        /// Bouts still waiting for a name.
        var unnamed: [ActiveBouts.Bout] = []
        /// Named or added by you.
        var logged: [ContextEvent] = []
        /// Recorded by a watch as a non-gym activity.
        var recorded: [DetectedWorkout] = []

        var isEmpty: Bool { unnamed.isEmpty && logged.isEmpty && recorded.isEmpty }
        var minutes: Double {
            unnamed.reduce(0) { $0 + $1.minutes } + logged.reduce(0) { $0 + ($1.value ?? 0) }
                + recorded.reduce(0) { $0 + $1.minutes }
        }
    }

    static func day(_ date: Date, context: ModelContext) async -> Day {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date

        async let weight = latestWeight()
        let workouts = await WorkoutDetector.workouts(on: date, context: context)
        let samples = await heartRate(from: start, to: end, context: context)
        let logged = loggedEvents(from: start, to: end, context: context)

        // Anything already recorded (by any app, padded a few minutes) or
        // named isn't a mystery bout.
        var busy = await WorkoutDetector.busyIntervals(on: date, context: context)
        busy += logged.map { DateInterval(start: $0.timestamp, end: $0.timestamp.addingTimeInterval(($0.value ?? 0) * 60)) }

        var settings = ActiveBouts.Settings()
        settings.weightLbs = await weight ?? 200
        let named = Set(logged.compactMap(\.sourceExternalID))
        let dismissed = dismissedIDs
        let found = ActiveBouts.find(in: samples, excluding: busy, settings: settings)
            .filter { !named.contains($0.id) && !dismissed.contains($0.id) }
        let bouts = await accountForWalking(found, from: start, to: end)

        return Day(unnamed: bouts, logged: logged, recorded: workouts.filter { $0.kind == .other })
    }

    /// Walking and running Health already logged (steps, distance — e.g.
    /// Mile A Day without a workout) is already in your mile and steps:
    /// stretches that are mostly that drop out, mixed ones keep only the
    /// non-walking share of their calories.
    private static func accountForWalking(_ bouts: [ActiveBouts.Bout], from start: Date, to end: Date) async -> [ActiveBouts.Bout] {
        guard !bouts.isEmpty else { return bouts }
        #if canImport(HealthKit)
        let health = HealthKitManager.shared
        async let stepSamples = try? health.fetchIntervalSamples(.stepCount, unit: .count(), from: start, to: end)
        async let distanceSamples = try? health.fetchIntervalSamples(.distanceWalkingRunning, unit: .mile(), from: start, to: end)
        let steps = await stepSamples ?? [], distance = await distanceSamples ?? []
        guard !steps.isEmpty || !distance.isEmpty else { return bouts }
        return bouts.compactMap { b in
            switch ActivityAccounting.classify(start: b.start, end: b.end, steps: steps, distance: distance) {
            case .alreadyCounted:
                return nil
            case .mixed(let share):
                var kept = b
                kept.calories = (b.calories * (1 - share)).rounded()
                return kept
            case .unexplained:
                return b
            }
        }
        #else
        return bouts
        #endif
    }

    // MARK: - Naming

    static func name(_ bout: ActiveBouts.Bout, as name: String, context: ModelContext) {
        add(name: name, start: bout.start, minutes: bout.minutes.rounded(), calories: bout.calories,
            averageBPM: bout.averageBPM, externalID: bout.id, context: context)
    }

    static func add(name: String, start: Date, minutes: Double, calories: Double?, averageBPM: Double? = nil,
                    externalID: String? = nil, context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, minutes > 0 else { return }
        let json = averageBPM.map { "{\"averageBPM\":\(Int($0))}" }
        let event = ContextEvent(timestamp: start, kind: .workout, subtype: subtype, value: minutes,
                                 secondaryValue: calories, unit: "min", text: trimmed, structuredJSON: json,
                                 source: externalID == nil ? .manual : .healthkit, sourceExternalID: externalID)
        context.insert(event)
        try? context.save()
        if trimmed == ActiveBouts.intimacy {
            let id = event.id
            Task {
                await HealthWriteBack.requestAccessIfNeeded()
                HealthWriteBack.syncIntimacy(eventID: id, start: start, minutes: minutes)
            }
        }
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    static func delete(_ event: ContextEvent, context: ModelContext) {
        if event.text == ActiveBouts.intimacy { HealthWriteBack.removeIntimacy(eventID: event.id) }
        context.delete(event)
        try? context.save()
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    /// "That wasn't anything" — stop asking about it.
    static func dismiss(_ bout: ActiveBouts.Bout) {
        var ids = dismissedIDs
        ids.insert(bout.id)
        UserDefaults.standard.set(Array(ids.suffix(200)), forKey: dismissedKey)
    }

    private static var dismissedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    /// What you've called past bouts, for suggestions.
    static func history(context: ModelContext, days: Int = 120) -> [(name: String, start: Date)] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return loggedEvents(from: since, to: Date().addingTimeInterval(86_400), context: context)
            .compactMap { e in e.text.map { ($0, e.timestamp) } }
    }

    private static func loggedEvents(from start: Date, to end: Date, context: ModelContext) -> [ContextEvent] {
        let workout = ContextEvent.Kind.workout.rawValue, fun = subtype
        let desc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.kindRaw == workout && $0.subtype == fun && $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\.timestamp)])
        return (try? context.fetch(desc)) ?? []
    }

    // MARK: - Heart rate

    private static func heartRate(from start: Date, to end: Date, context: ModelContext) async -> [ActiveBouts.Sample] {
        var out: [ActiveBouts.Sample] = []
        #if canImport(HealthKit)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        if let hk = try? await HealthKitManager.shared.fetchSamples(.heartRate, unit: bpm, from: start, to: end) {
            out += hk.map { .init(date: $0.date, bpm: $0.value) }
        }
        #endif
        if GoogleHealthSyncService.isConnected {
            out += await GoogleHealthSyncService(modelContext: context).heartRate(from: start, to: end)
        }
        return out
    }

    private static func latestWeight() async -> Double? {
        #if canImport(HealthKit)
        return try? await HealthKitManager.shared.fetchLatest(.bodyMass, unit: .pound(), withinDays: 30)?.value
        #else
        return nil
        #endif
    }
}

extension GoogleHealthSyncService {
    /// Every heart-rate reading in a window (Pixel Watch, Fitbit).
    func heartRate(from start: Date, to end: Date) async -> [ActiveBouts.Sample] {
        // Bounded on both ends: a past day with only a lower bound pulled
        // every reading since then, page after page, and stalled the view.
        let field = "heart_rate.sample_time.physical_time"
        let lower = "\(field) >= \"\(GHTime.rfc3339(start))\""
        let bounded = try? await GoogleHealthAPI.shared.list(
            "heart-rate", filter: "\(lower) AND \(field) < \"\(GHTime.rfc3339(end))\"", pageSize: 1000, maxPages: 8)
        // If the API won't take the AND, a few pages from the start still covers most of a window.
        let fallback: [GHDataPoint]?
        if bounded == nil {
            fallback = try? await GoogleHealthAPI.shared.list("heart-rate", filter: lower, pageSize: 1000, maxPages: 4)
        } else {
            fallback = nil
        }
        guard let points = bounded ?? fallback else { return [] }
        return points.compactMap { p in
            guard let hr = p.heartRate, let bpm = hr.beatsPerMinute?.value,
                  let t = GHTime.parse(hr.sampleTime?.physicalTime), t < end else { return nil }
            return ActiveBouts.Sample(date: t, bpm: Double(bpm))
        }
    }
}
