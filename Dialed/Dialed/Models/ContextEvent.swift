//
//  ContextEvent.swift
//  Dialed
//
//  Universal timeline event — every meal, drink, workout, mood note, biometric,
//  weather change, etc. lives in this single table. Powers the Timeline view
//  and gives the on-device AI a unified history to reason over.
//

import Foundation
import SwiftData

@Model
final class ContextEvent {
    @Attribute(.unique) var id: UUID

    /// When the event happened in the real world.
    var timestamp: Date

    /// The "app day" this event belongs to (start-of-day, respects 4 AM cutoff).
    /// Lets us cheaply query "everything that happened on day X" without
    /// scanning timestamps.
    var logicalDate: Date

    /// Stable raw value of `Kind` enum.
    var kindRaw: String

    /// Free-form subtype within a kind. E.g. kind=caffeine, subtype="coffee" / "preworkout".
    /// kind=workout, subtype="push" / "pull" / "run".
    var subtype: String?

    /// Primary numeric value with semantics determined by kind.
    /// - water: ounces
    /// - caffeine: milligrams
    /// - alcohol: standard drinks
    /// - meal: calories
    /// - mood / energy: 1–5 rating
    /// - workout: duration minutes
    /// - biometric_event: depends on subtype
    var value: Double?

    /// Secondary numeric value for kinds that need two numbers.
    /// - meal: protein grams (when value=calories)
    /// - workout: calories burned (when value=duration)
    var secondaryValue: Double?

    /// Optional unit hint for display ("oz", "mg", "min", "kcal", "g").
    var unit: String?

    /// Short title or free-text body (journal, note, voice transcript).
    var text: String?

    /// JSON bag for kind-specific structured data we don't want first-class columns for.
    /// Example for kind=meal: `{"items":["chicken","rice"],"photoFilename":"..."}`.
    var structuredJSON: String?

    /// Where this event came from. Used for dedup and trust scoring.
    var sourceRaw: String

    /// External ID from the source (Fitbit sleep ID, HealthKit UUID, etc.) for dedup.
    var sourceExternalID: String?

    /// Optional link to another event ("this mood note is about that workout").
    var relatedEventID: UUID?

    /// AI-generated annotation populated by the nightly insight pass.
    /// Example: "REM dropped 28 min — likely the late pasta meal."
    var aiAnnotation: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        timestamp: Date,
        kind: Kind,
        subtype: String? = nil,
        value: Double? = nil,
        secondaryValue: Double? = nil,
        unit: String? = nil,
        text: String? = nil,
        structuredJSON: String? = nil,
        source: Source = .manual,
        sourceExternalID: String? = nil,
        relatedEventID: UUID? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.logicalDate = Self.logicalDate(for: timestamp)
        self.kindRaw = kind.rawValue
        self.subtype = subtype
        self.value = value
        self.secondaryValue = secondaryValue
        self.unit = unit
        self.text = text
        self.structuredJSON = structuredJSON
        self.sourceRaw = source.rawValue
        self.sourceExternalID = sourceExternalID
        self.relatedEventID = relatedEventID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Accessors

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    // MARK: - Logical date

    /// Maps a real timestamp to the "app day" using the 4 AM cutoff.
    /// 1 AM Tuesday → logical date = Monday.
    static func logicalDate(for timestamp: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        let base = calendar.startOfDay(for: timestamp)
        if hour < Constants.dayCutoffHour {
            return calendar.date(byAdding: .day, value: -1, to: base) ?? base
        }
        return base
    }
}

// MARK: - Kind

extension ContextEvent {
    enum Kind: String, Codable, CaseIterable {
        // Ingested / consumed
        case meal
        case water
        case caffeine
        case alcohol
        case supplement

        // Activity
        case workout
        case steps          // discrete event ("walked 1.2 mi @ lunch") — for daily totals see DayLog
        case mile

        // Sleep is also represented richly in SleepSession; this is a Timeline anchor.
        case sleep

        // Subjective
        case mood           // 1–5 valence
        case energy         // 1–5 felt energy
        case stress         // 1–5 perceived stress
        case soreness       // 1–5
        case journal        // free text
        case note           // short note

        // Routine
        case routineTask    // marking a daily routine task done (replaces ChecklistItem in Timeline)

        // Auto-ingested context
        case biometricEvent // e.g. HRV spike, low SpO2 — point-in-time samples live in BiometricSnapshot
        case weather
        case calendarEvent  // EventKit
        case location       // significant location change

        // AI
        case aiInsight      // synthesized observation surfaced on the Timeline
    }

    enum Source: String, Codable {
        case manual
        case voice
        case healthkit
        case fitbit
        case weatherkit
        case eventkit
        case ai
        case migration  // imported from legacy DayLog during the 1.x → 2.0 migration
    }
}

// MARK: - Convenience builders

extension ContextEvent {
    static func water(_ ounces: Double, at time: Date = Date(), source: Source = .manual) -> ContextEvent {
        ContextEvent(timestamp: time, kind: .water, value: ounces, unit: "oz", source: source)
    }

    static func caffeine(milligrams: Double, subtype: String? = "coffee", at time: Date = Date()) -> ContextEvent {
        ContextEvent(timestamp: time, kind: .caffeine, subtype: subtype, value: milligrams, unit: "mg")
    }

    static func alcohol(standardDrinks: Double, at time: Date = Date()) -> ContextEvent {
        ContextEvent(timestamp: time, kind: .alcohol, value: standardDrinks, unit: "drinks")
    }

    static func meal(calories: Double, protein: Double, items: [String] = [], at time: Date = Date()) -> ContextEvent {
        let payload = MealPayload(items: items)
        let json = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
        return ContextEvent(
            timestamp: time,
            kind: .meal,
            value: calories,
            secondaryValue: protein,
            unit: "kcal",
            structuredJSON: json
        )
    }

    static func mood(_ rating: Int, note: String? = nil, at time: Date = Date()) -> ContextEvent {
        ContextEvent(timestamp: time, kind: .mood, value: Double(rating), text: note)
    }

    static func energy(_ rating: Int, at time: Date = Date()) -> ContextEvent {
        ContextEvent(timestamp: time, kind: .energy, value: Double(rating))
    }

    static func journal(_ body: String, at time: Date = Date()) -> ContextEvent {
        ContextEvent(timestamp: time, kind: .journal, text: body)
    }
}

// MARK: - Structured payloads

private struct MealPayload: Codable {
    var items: [String]
}
