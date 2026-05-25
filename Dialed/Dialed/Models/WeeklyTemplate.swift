//
//  WeeklyTemplate.swift
//  Dialed
//
//  A repeating skeleton week. The planner walks the template, anchors it to
//  your actual wake time and state for the day, and produces a DailyPlan.
//
//  The template is the "stable" representation — you edit it once, and the
//  planner re-generates concrete DailyPlans every morning. This separation
//  is what lets the schedule adapt to wake time, recovery, and calendar
//  without losing the bones of your week.
//

import Foundation
import SwiftData

@Model
final class WeeklyTemplate {
    @Attribute(.unique) var id: UUID

    /// Display name — "My Default Week", "Cut Phase", "Vacation".
    var name: String

    /// Only one template is "active" at a time; the planner picks this one
    /// when generating tomorrow's plan. Switching templates is a single
    /// toggle in Settings.
    var isActive: Bool

    var createdAt: Date
    var updatedAt: Date

    /// Cascade: deleting the template wipes its blocks.
    @Relationship(deleteRule: .cascade, inverse: \TemplateBlock.template)
    var blocks: [TemplateBlock]?

    init(name: String, isActive: Bool = false) {
        self.id = UUID()
        self.name = name
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class TemplateBlock {
    @Attribute(.unique) var id: UUID

    var template: WeeklyTemplate?

    /// Which weekdays this block runs on. Stored as a bitmask so a single
    /// block can run on multiple days (Mon/Wed/Fri morning workout).
    /// Bit 0 = Sunday … bit 6 = Saturday, matching Calendar.weekday - 1.
    var weekdayMask: Int

    /// What kind of block this is — drives icon, color, and behavior.
    var kindRaw: String

    /// Display title — "Morning workout", "Lunch + vitamins", "Wind down".
    var title: String

    /// Optional subtitle / instructions.
    var blockDescription: String?

    /// Anchor mode: should this block be pinned to a wall-clock time, or
    /// relative to wake/sleep time? Adaptive is the whole point of the
    /// rewrite — if you wake at 8 instead of 7, your AM skincare should
    /// slide an hour later automatically.
    var anchorRaw: String

    /// Anchor offset in minutes. Interpretation depends on anchorRaw:
    /// - wallClock: minutes from midnight
    /// - afterWake: minutes after wake time
    /// - beforeSleep: minutes before target sleep time
    var anchorOffsetMinutes: Int

    /// Duration in minutes (0 if it's a moment-in-time event).
    var durationMinutes: Int

    /// Optional: only run on days where recovery is at least this threshold.
    /// Used to auto-skip hard workouts on low-recovery days. nil = always run.
    var minRecovery: Int?

    /// Whether completion of this block counts toward weekly adherence stats.
    var countsForAdherence: Bool

    /// Sort order within a day — used as a tiebreaker when two blocks share
    /// a resolved time.
    var sortOrder: Int

    var createdAt: Date

    init(
        kind: Kind,
        title: String,
        blockDescription: String? = nil,
        weekdayMask: Int = WeekdayMask.everyDay,
        anchor: Anchor,
        anchorOffsetMinutes: Int,
        durationMinutes: Int = 0,
        minRecovery: Int? = nil,
        countsForAdherence: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.weekdayMask = weekdayMask
        self.kindRaw = kind.rawValue
        self.title = title
        self.blockDescription = blockDescription
        self.anchorRaw = anchor.rawValue
        self.anchorOffsetMinutes = anchorOffsetMinutes
        self.durationMinutes = durationMinutes
        self.minRecovery = minRecovery
        self.countsForAdherence = countsForAdherence
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .routine }
        set { kindRaw = newValue.rawValue }
    }

    var anchor: Anchor {
        get { Anchor(rawValue: anchorRaw) ?? .wallClock }
        set { anchorRaw = newValue.rawValue }
    }

    /// True if this block runs on the given weekday (1 = Sunday).
    func runs(on weekday: Int) -> Bool {
        let bit = weekday - 1
        guard (0..<7).contains(bit) else { return false }
        return (weekdayMask & (1 << bit)) != 0
    }
}

// MARK: - Kind + Anchor + Mask

extension TemplateBlock {
    enum Kind: String, Codable, CaseIterable {
        case wake             // morning anchor — wake-up cue, hydration prompt
        case skincare
        case supplement
        case hydration
        case meal
        case caffeine
        case workout          // strength / push / pull / legs / etc.
        case cardio
        case deepWork         // focus block
        case rest
        case windDown         // pre-sleep routine
        case sleep            // sleep target anchor
        case mood             // self-report check-in
        case routine          // generic fallback

        var defaultIcon: String {
            switch self {
            case .wake:        return "sun.max.fill"
            case .skincare:    return "face.smiling.fill"
            case .supplement:  return "pills.fill"
            case .hydration:   return "drop.fill"
            case .meal:        return "fork.knife"
            case .caffeine:    return "cup.and.saucer.fill"
            case .workout:     return "figure.strengthtraining.traditional"
            case .cardio:      return "figure.run"
            case .deepWork:    return "brain.head.profile"
            case .rest:        return "leaf.fill"
            case .windDown:    return "moon.stars.fill"
            case .sleep:       return "bed.double.fill"
            case .mood:        return "heart.fill"
            case .routine:     return "checkmark.circle.fill"
            }
        }

        var defaultPillar: AppColors.Pillar {
            switch self {
            case .wake, .meal, .caffeine, .supplement: return .energy
            case .workout, .cardio:                     return .strain
            case .rest, .windDown, .sleep, .skincare:   return .recovery
            case .deepWork, .hydration, .mood, .routine: return .readiness
            }
        }
    }

    enum Anchor: String, Codable {
        /// Pinned to a wall-clock time (anchorOffsetMinutes from midnight).
        case wallClock
        /// Sliding — minutes after the day's actual wake time.
        case afterWake
        /// Sliding — minutes before the target sleep time.
        case beforeSleep
    }

    enum WeekdayMask {
        /// Bit 0 = Sunday … bit 6 = Saturday.
        static let everyDay = 0b1111111
        static let weekdays = 0b0111110   // Mon–Fri
        static let weekends = 0b1000001   // Sat + Sun

        static func single(_ weekday: Int) -> Int {
            (0..<7).contains(weekday - 1) ? (1 << (weekday - 1)) : 0
        }

        static func mask(for weekdays: [Int]) -> Int {
            weekdays.reduce(0) { acc, w in acc | single(w) }
        }
    }
}

// MARK: - Default template

extension WeeklyTemplate {
    /// The starter template a user gets the first time they open the new
    /// Plan tab. Modeled on Rob's existing checklist schedule, but with
    /// proper anchors so it adapts to actual wake time.
    @MainActor
    static func seedDefault(into context: ModelContext) -> WeeklyTemplate {
        let template = WeeklyTemplate(name: "Default Week", isActive: true)
        context.insert(template)

        let mask = TemplateBlock.WeekdayMask.self

        let blocks: [TemplateBlock] = [
            // Mornings — anchor to wake
            TemplateBlock(
                kind: .wake, title: "Wake + first water",
                blockDescription: "16oz right after waking",
                weekdayMask: mask.everyDay, anchor: .afterWake, anchorOffsetMinutes: 0,
                durationMinutes: 5, sortOrder: 0
            ),
            TemplateBlock(
                kind: .skincare, title: "AM skincare",
                blockDescription: "Rinse face + CeraVe AM",
                weekdayMask: mask.everyDay, anchor: .afterWake, anchorOffsetMinutes: 30,
                durationMinutes: 5, sortOrder: 1
            ),
            TemplateBlock(
                kind: .caffeine, title: "First coffee",
                blockDescription: "~90 min after waking (avoid adenosine rebound)",
                weekdayMask: mask.everyDay, anchor: .afterWake, anchorOffsetMinutes: 90,
                durationMinutes: 10, sortOrder: 2
            ),

            // Midday
            TemplateBlock(
                kind: .supplement, title: "Lunch + vitamins",
                blockDescription: "Fish oil, D3/K2 — with food",
                weekdayMask: mask.everyDay, anchor: .wallClock, anchorOffsetMinutes: 12 * 60,
                durationMinutes: 30, sortOrder: 3
            ),

            // Late afternoon
            TemplateBlock(
                kind: .supplement, title: "Creatine",
                blockDescription: "5g — pre-workout window",
                weekdayMask: mask.everyDay, anchor: .wallClock, anchorOffsetMinutes: 17 * 60 + 15,
                durationMinutes: 5, sortOrder: 4
            ),

            // Workouts — weekday split. minRecovery: 50 = auto-skip on poor recovery days.
            TemplateBlock(
                kind: .workout, title: "Push (chest/shoulders)",
                blockDescription: "60m strength",
                weekdayMask: mask.single(2), anchor: .wallClock, anchorOffsetMinutes: 17 * 60 + 30,
                durationMinutes: 60, minRecovery: 50, sortOrder: 5
            ),
            TemplateBlock(
                kind: .workout, title: "Pull (back/bis)",
                blockDescription: "60m strength",
                weekdayMask: mask.single(3), anchor: .wallClock, anchorOffsetMinutes: 17 * 60 + 30,
                durationMinutes: 60, minRecovery: 50, sortOrder: 5
            ),
            TemplateBlock(
                kind: .workout, title: "Legs",
                blockDescription: "60m strength",
                weekdayMask: mask.single(4), anchor: .wallClock, anchorOffsetMinutes: 17 * 60 + 30,
                durationMinutes: 60, minRecovery: 60, sortOrder: 5
            ),
            TemplateBlock(
                kind: .workout, title: "Arms + core",
                blockDescription: "45m strength",
                weekdayMask: mask.single(5), anchor: .wallClock, anchorOffsetMinutes: 17 * 60 + 30,
                durationMinutes: 45, minRecovery: 45, sortOrder: 5
            ),
            TemplateBlock(
                kind: .workout, title: "Upper pump",
                blockDescription: "45m strength",
                weekdayMask: mask.single(6), anchor: .wallClock, anchorOffsetMinutes: 17 * 60 + 30,
                durationMinutes: 45, minRecovery: 45, sortOrder: 5
            ),
            TemplateBlock(
                kind: .rest, title: "Rest day",
                blockDescription: "Active recovery — walk, mobility, hydrate",
                weekdayMask: mask.single(1), anchor: .wallClock, anchorOffsetMinutes: 17 * 60 + 30,
                durationMinutes: 0, sortOrder: 5
            ),

            // Evening
            TemplateBlock(
                kind: .meal, title: "Dinner",
                blockDescription: "Protein target + slow carbs",
                weekdayMask: mask.everyDay, anchor: .wallClock, anchorOffsetMinutes: 19 * 60,
                durationMinutes: 30, sortOrder: 6
            ),
            TemplateBlock(
                kind: .windDown, title: "Wind down",
                blockDescription: "Dim lights, no scrolling",
                weekdayMask: mask.everyDay, anchor: .beforeSleep, anchorOffsetMinutes: 60,
                durationMinutes: 60, sortOrder: 7
            ),
            TemplateBlock(
                kind: .skincare, title: "PM skincare",
                blockDescription: "Wash + CeraVe PM",
                weekdayMask: mask.everyDay, anchor: .beforeSleep, anchorOffsetMinutes: 30,
                durationMinutes: 5, sortOrder: 8
            ),
            TemplateBlock(
                kind: .sleep, title: "Sleep target",
                blockDescription: "Lights out — aim for 7.5h",
                weekdayMask: mask.everyDay, anchor: .beforeSleep, anchorOffsetMinutes: 0,
                durationMinutes: 0, sortOrder: 9
            )
        ]

        for block in blocks {
            block.template = template
            context.insert(block)
        }
        template.blocks = blocks
        return template
    }
}
