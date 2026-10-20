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

        // Anything already recorded or named isn't a mystery bout.
        var busy = workouts.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        busy += logged.map { DateInterval(start: $0.timestamp, end: $0.timestamp.addingTimeInterval(($0.value ?? 0) * 60)) }

        var settings = ActiveBouts.Settings()
        settings.weightLbs = await weight ?? 200
        let named = Set(logged.compactMap(\.sourceExternalID))
        let dismissed = dismissedIDs
        let bouts = ActiveBouts.find(in: samples, excluding: busy, settings: settings)
            .filter { !named.contains($0.id) && !dismissed.contains($0.id) }

        return Day(unnamed: bouts, logged: logged, recorded: workouts.filter { $0.kind == .other })
    }

    // MARK: - Naming

    static func name(_ bout: ActiveBouts.Bout, as name: String, protectionUsed: Bool? = nil, context: ModelContext) {
        add(name: name, start: bout.start, minutes: bout.minutes.rounded(), calories: bout.calories,
            averageBPM: bout.averageBPM, externalID: bout.id, protectionUsed: protectionUsed, context: context)
    }

    static func add(name: String, start: Date, minutes: Double, calories: Double?, averageBPM: Double? = nil,
                    externalID: String? = nil, protectionUsed: Bool? = nil, context: ModelContext) {
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
                HealthWriteBack.syncIntimacy(eventID: id, start: start, minutes: minutes, protectionUsed: protectionUsed)
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
        guard let points = try? await GoogleHealthAPI.shared.list(
            "heart-rate",
            filter: "heart_rate.sample_time.physical_time >= \"\(GHTime.rfc3339(start))\"",
            pageSize: 1000, maxPages: 20
        ) else { return [] }
        return points.compactMap { p in
            guard let hr = p.heartRate, let bpm = hr.beatsPerMinute?.value,
                  let t = GHTime.parse(hr.sampleTime?.physicalTime), t < end else { return nil }
            return ActiveBouts.Sample(date: t, bpm: Double(bpm))
        }
    }
}
