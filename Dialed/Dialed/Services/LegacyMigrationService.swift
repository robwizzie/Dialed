//
//  LegacyMigrationService.swift
//  Dialed
//
//  One-time backfill that converts legacy DayLog data into ContextEvent rows
//  so the new Timeline view (Phase 4) has history to render. Idempotent and
//  gated by a UserDefaults flag.
//
//  We do NOT delete the legacy data — it keeps existing screens (TodayView,
//  CalendarView) working unchanged during the transition. Once all screens
//  read from ContextEvent we'll add a follow-up cleanup pass.
//

import Foundation
import SwiftData

@MainActor
enum LegacyMigrationService {
    /// Bump this when changing migration semantics. The flag stores the last
    /// version we ran; on app launch we re-run if our `currentVersion` is higher.
    static let currentVersion = 1

    private static let flagKey = "legacyMigration.lastVersion"

    /// True if we should run the migration now.
    static var needsMigration: Bool {
        let last = UserDefaults.standard.integer(forKey: flagKey)
        return last < currentVersion
    }

    /// Run the migration. Safe to call repeatedly — short-circuits when already done.
    static func runIfNeeded(context: ModelContext) {
        guard needsMigration else { return }

        do {
            let dayLogs = try context.fetch(FetchDescriptor<DayLog>())
            var inserted = 0
            for day in dayLogs {
                inserted += backfill(day: day, context: context)
            }
            // Flush before setting the flag — otherwise a crash between insert and
            // autosave would leave us thinking we'd migrated when we hadn't.
            try context.save()
            UserDefaults.standard.set(currentVersion, forKey: flagKey)
            print("✅ [Migration] Backfilled \(inserted) ContextEvent rows from \(dayLogs.count) DayLogs")
        } catch {
            // Don't trip the flag on failure — we'll try again on next launch.
            print("❌ [Migration] Failed: \(error)")
        }
    }

    // MARK: - Per-day backfill

    /// Returns the number of ContextEvent rows inserted for this day.
    private static func backfill(day: DayLog, context: ModelContext) -> Int {
        var inserted = 0
        let dayStart = Calendar.current.startOfDay(for: day.date)

        // Meals → meal events (one per FoodEntry).
        for food in (day.foodEntries ?? []) {
            let externalID = "legacy-food-\(food.id.uuidString)"
            if existsEvent(externalID: externalID, in: context) { continue }
            let event = ContextEvent(
                timestamp: food.timestamp,
                kind: .meal,
                value: food.calories,
                secondaryValue: food.proteinGrams,
                unit: "kcal",
                text: food.name,
                source: .migration,
                sourceExternalID: externalID
            )
            context.insert(event)
            inserted += 1
        }

        // Aggregate water for the day. We don't have per-sip data, so we model
        // it as a single midday "summary" event with the daily total.
        if day.waterOz > 0 {
            let externalID = "legacy-water-\(externalDateID(dayStart))"
            if !existsEvent(externalID: externalID, in: context) {
                let event = ContextEvent(
                    timestamp: Self.noonOf(dayStart),
                    kind: .water,
                    value: day.waterOz,
                    unit: "oz",
                    text: "Daily water (legacy)",
                    source: .migration,
                    sourceExternalID: externalID
                )
                context.insert(event)
                inserted += 1
            }
        }

        // Workout — one event per WorkoutLog.
        if let workout = day.workoutLog {
            let externalID = "legacy-workout-\(workout.id.uuidString)"
            if !existsEvent(externalID: externalID, in: context) {
                let event = ContextEvent(
                    timestamp: workout.startTime ?? workout.loggedAt,
                    kind: .workout,
                    subtype: workout.tag,
                    value: workout.durationMinutes.map(Double.init),
                    secondaryValue: workout.caloriesBurned.map(Double.init),
                    unit: "min",
                    text: workout.notes,
                    source: .migration,
                    sourceExternalID: externalID
                )
                context.insert(event)
                inserted += 1
            }
        }

        // Mile — synthesized event when the legacy flag is set.
        if day.mileCompleted {
            let externalID = "legacy-mile-\(externalDateID(dayStart))"
            if !existsEvent(externalID: externalID, in: context) {
                let event = ContextEvent(
                    timestamp: Self.noonOf(dayStart),
                    kind: .mile,
                    value: day.mileDistance,
                    secondaryValue: day.mileTimeSeconds.map(Double.init),
                    unit: "mi",
                    source: .migration,
                    sourceExternalID: externalID
                )
                context.insert(event)
                inserted += 1
            }
        }

        // Sleep — bridge to SleepSession + ContextEvent anchor.
        if let durationMin = day.sleepDurationMinutes, durationMin > 0 {
            let externalID = "legacy-sleep-\(externalDateID(dayStart))"
            // ContextEvent anchor
            if !existsEvent(externalID: externalID, in: context) {
                let approxStart = Self.elevenPM(of: Calendar.current.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart)
                let event = ContextEvent(
                    timestamp: approxStart,
                    kind: .sleep,
                    value: Double(durationMin),
                    unit: "min",
                    text: "Sleep \(durationMin / 60)h \(durationMin % 60)m (legacy)",
                    source: .migration,
                    sourceExternalID: externalID
                )
                context.insert(event)
                inserted += 1
            }

            // SleepSession — only insert if we don't already have one for this date.
            let sleepExternalID = "legacy-sleep-session-\(externalDateID(dayStart))"
            let descriptor = FetchDescriptor<SleepSession>(
                predicate: #Predicate { $0.sourceExternalID == sleepExternalID }
            )
            if (try? context.fetch(descriptor))?.isEmpty ?? true {
                // Approximate: 11 PM previous day → wake = sleepEnd = startOfDay + durationMin/60 hrs.
                let approxStart = Self.elevenPM(of: Calendar.current.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart)
                let approxEnd = approxStart.addingTimeInterval(TimeInterval(durationMin * 60))
                let session = SleepSession(
                    startTime: approxStart,
                    endTime: approxEnd,
                    inBedMinutes: durationMin + (day.sleepAwakeMinutes ?? 0),
                    asleepMinutes: durationMin,
                    source: .manual,
                    sourceExternalID: sleepExternalID
                )
                session.deepMinutes = day.sleepDeepMinutes
                session.remMinutes = day.sleepREMMinutes
                session.lightMinutes = day.sleepLightMinutes
                session.awakeMinutes = day.sleepAwakeMinutes
                session.efficiency = day.sleepEfficiency
                session.avgHRV = day.sleepHRV
                session.avgRestingHeartRate = day.sleepRestingHR
                session.computedSleepScore = day.sleepScore
                context.insert(session)
            }
        }

        // Checklist completions → routineTask events.
        for item in (day.checklistItems ?? []) where item.checklistStatus == .done {
            let externalID = "legacy-task-\(item.id.uuidString)"
            if existsEvent(externalID: externalID, in: context) { continue }
            let when = item.completedAt ?? dayStart
            let event = ContextEvent(
                timestamp: when,
                kind: .routineTask,
                subtype: item.type,
                value: item.customPoints.map(Double.init),
                text: item.displayTitle,
                source: .migration,
                sourceExternalID: externalID
            )
            context.insert(event)
            inserted += 1
        }

        return inserted
    }

    // MARK: - Helpers

    private static func existsEvent(externalID: String, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.sourceExternalID == externalID }
        )
        return (try? context.fetch(descriptor))?.isEmpty == false
    }

    private static func externalDateID(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    private static func noonOf(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    private static func elevenPM(of date: Date) -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: date) ?? date
    }
}
