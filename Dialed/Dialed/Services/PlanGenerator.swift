//
//  PlanGenerator.swift
//  Dialed
//
//  Resolves an abstract WeeklyTemplate into a concrete DailyPlan for a
//  specific date, given the day's wake/sleep anchors and current state.
//
//  Adapts to:
//    - wake time (afterWake anchors slide automatically)
//    - sleep target (beforeSleep anchors slide automatically)
//    - recovery score (low-recovery days auto-skip blocks with minRecovery)
//
//  Pure logic for the resolution math; SwiftData orchestration for upsert.
//

import Foundation
import SwiftData

@MainActor
enum PlanGenerator {

    struct Inputs {
        var date: Date
        var template: WeeklyTemplate
        /// The wake time anchor (when the user actually woke up, or their
        /// expected wake time if the day hasn't started yet).
        var wakeTime: Date
        /// The target sleep time for the end of the day.
        var sleepTargetTime: Date
        /// Current recovery score (0-100). Drives the auto-skip filter.
        var recoveryScore: Int?
        /// Current readiness score (0-100). Stored on the plan for transparency.
        var readinessScore: Int?
    }

    // MARK: - Pure resolution

    /// Resolve every block in the template to a concrete (time, included?)
    /// for the given day. Doesn't touch SwiftData — easy to unit-test.
    static func resolveBlocks(_ inputs: Inputs) -> [ResolvedBlock] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: inputs.date)  // 1 = Sun

        guard let blocks = inputs.template.blocks else { return [] }

        return blocks
            .filter { $0.runs(on: weekday) }
            .compactMap { block -> ResolvedBlock? in
                // Auto-skip when recovery is below the block's threshold.
                if let min = block.minRecovery,
                   let rec = inputs.recoveryScore,
                   rec < min {
                    return ResolvedBlock(
                        templateBlock: block,
                        startTime: resolveStart(block: block, inputs: inputs),
                        included: false,
                        skipReason: "Recovery \(rec) < target \(min) — skipped to protect tomorrow"
                    )
                }
                let start = resolveStart(block: block, inputs: inputs)
                return ResolvedBlock(
                    templateBlock: block,
                    startTime: start,
                    included: true,
                    skipReason: nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime < rhs.startTime
                }
                return lhs.templateBlock.sortOrder < rhs.templateBlock.sortOrder
            }
    }

    /// Resolved value object — what the day actually contains, before we
    /// write to SwiftData.
    struct ResolvedBlock {
        let templateBlock: TemplateBlock
        let startTime: Date
        let included: Bool
        let skipReason: String?
    }

    /// Compute the wall-clock start time for one template block on a given day.
    static func resolveStart(block: TemplateBlock, inputs: Inputs) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: inputs.date)

        switch block.anchor {
        case .wallClock:
            return dayStart.addingTimeInterval(TimeInterval(block.anchorOffsetMinutes * 60))

        case .afterWake:
            return inputs.wakeTime.addingTimeInterval(TimeInterval(block.anchorOffsetMinutes * 60))

        case .beforeSleep:
            return inputs.sleepTargetTime.addingTimeInterval(TimeInterval(-block.anchorOffsetMinutes * 60))
        }
    }

    // MARK: - SwiftData orchestration

    /// Upsert today's plan: re-resolve from the template, preserve manual
    /// edits, update statuses for blocks that already exist (matching by
    /// sourceTemplateBlockID), and skip-flag blocks the recovery filter
    /// dropped today.
    @discardableResult
    static func generatePlan(
        inputs: Inputs,
        context: ModelContext
    ) throws -> DailyPlan {
        let dayStart = Calendar.current.startOfDay(for: inputs.date)

        // Find or create the DailyPlan row for this date.
        let existingPlanDescriptor = FetchDescriptor<DailyPlan>(
            predicate: #Predicate { $0.date == dayStart }
        )
        let plan = try context.fetch(existingPlanDescriptor).first
            ?? DailyPlan(
                date: dayStart,
                sourceTemplateID: inputs.template.id,
                anchorWakeTime: inputs.wakeTime,
                anchorSleepTime: inputs.sleepTargetTime,
                generationRecovery: inputs.recoveryScore,
                generationReadiness: inputs.readinessScore
            )

        if plan.modelContext == nil {
            context.insert(plan)
        } else {
            plan.sourceTemplateID = inputs.template.id
            plan.anchorWakeTime = inputs.wakeTime
            plan.anchorSleepTime = inputs.sleepTargetTime
            plan.generationRecovery = inputs.recoveryScore
            plan.generationReadiness = inputs.readinessScore
            plan.generatedAt = Date()
        }

        let resolved = resolveBlocks(inputs)
        var existing = (plan.blocks ?? [])
            .reduce(into: [UUID: PlanBlock]()) { acc, b in
                if let src = b.sourceTemplateBlockID { acc[src] = b }
            }

        for r in resolved {
            let block = existing.removeValue(forKey: r.templateBlock.id)
                ?? PlanBlock(
                    kind: r.templateBlock.kind,
                    title: r.templateBlock.title,
                    blockDescription: r.templateBlock.blockDescription,
                    startTime: r.startTime,
                    durationMinutes: r.templateBlock.durationMinutes,
                    sourceTemplateBlockID: r.templateBlock.id
                )

            // Always refresh times and metadata unless the user edited the
            // copy on this specific day.
            if !block.userEdited {
                block.kind = r.templateBlock.kind
                block.title = r.templateBlock.title
                block.blockDescription = r.templateBlock.blockDescription
                block.startTime = r.startTime
                block.durationMinutes = r.templateBlock.durationMinutes
            }

            // Apply recovery-filter skip.
            if !r.included {
                if block.status == .upcoming {
                    block.markSkipped(reason: r.skipReason)
                }
            } else if block.status == .skipped, block.skippedReason != nil {
                // Block was auto-skipped previously but now meets recovery — un-skip.
                block.status = .upcoming
                block.skippedReason = nil
            }

            if block.modelContext == nil {
                block.plan = plan
                context.insert(block)
            }
            block.updatedAt = Date()
        }

        // Remove blocks that no longer correspond to the template (e.g.
        // user deleted a template block). Skip manual ad-hoc blocks
        // (sourceTemplateBlockID == nil) — those belong to the user.
        for orphan in existing.values where !orphan.userEdited {
            context.delete(orphan)
        }

        // Refresh notifications off the new plan state. Also wipes the
        // legacy ChecklistItem cron reminders the first time we run — the
        // plan is the source of truth now.
        PlanNotificationScheduler.cancelLegacyChecklistNotifications()
        Task { await PlanNotificationScheduler.scheduleNotifications(for: plan) }

        // Persist yesterday's score snapshot — by the time the next day's
        // plan is generated, the prior day's biometric + sleep data has
        // settled, so the snapshot we write now is the final word on it.
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            DailyScoreSnapshotter.snapshot(for: yesterday, context: context)
        }

        return plan
    }

    // MARK: - Defaults

    /// Best-effort wake-time guess for `date` when we don't have a real
    /// observation yet. Uses the user's PersonalBaseline median wake time,
    /// falling back to 7:00 AM.
    static func defaultWakeTime(for date: Date, baseline: PersonalBaseline?) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        if let comps = baseline?.wakeTimeMedianComponents {
            return calendar.date(bySettingHour: comps.hour, minute: comps.minute,
                                  second: 0, of: dayStart) ?? dayStart
        }
        return calendar.date(bySettingHour: 7, minute: 0, second: 0, of: dayStart) ?? dayStart
    }

    /// Default sleep-target time. Uses the user's median bedtime if known,
    /// else 22:30. Always falls on the same calendar day as `date`.
    static func defaultSleepTime(for date: Date, baseline: PersonalBaseline?) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        if let comps = baseline?.bedtimeMedianComponents {
            // Bedtimes after midnight are stored in [0, 12)-ish — anchor them
            // to the *next* day so a 00:30 bedtime doesn't snap to noon.
            let hour = comps.hour
            let minute = comps.minute
            if hour < 12 {
                let next = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                return calendar.date(bySettingHour: hour, minute: minute,
                                      second: 0, of: next) ?? next
            }
            return calendar.date(bySettingHour: hour, minute: minute,
                                  second: 0, of: dayStart) ?? dayStart
        }
        return calendar.date(bySettingHour: 22, minute: 30, second: 0, of: dayStart) ?? dayStart
    }
}
