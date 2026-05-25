//
//  PlanNotificationScheduler.swift
//  Dialed
//
//  Schedules iOS local notifications off a DailyPlan's PlanBlocks. Replaces
//  the legacy cron-style ChecklistItem reminders. Idempotent — every call
//  cancels prior plan-block notifications for the same plan and re-schedules
//  from the current block state.
//
//  Notification timing per block kind:
//    - Workouts / deep work / cardio: pre-alert 5 min before + start alert
//    - Sleep target / wind down: start alert
//    - Wake: start alert (often AFTER you've woken — acts as a "first water"
//      cue)
//    - Everything else: start alert only
//
//  Identifier scheme (so we can selectively cancel):
//    plan_block_<planID>_<blockID>          — the main start alert
//    plan_block_pre_<planID>_<blockID>      — the optional pre-alert
//
//  Action buttons live on the PLAN_BLOCK category (Mark Done / Snooze 10m /
//  Skip), wired up in NotificationManager.registerCategories and handled in
//  AppDelegate.
//

import Foundation
import UserNotifications

@MainActor
enum PlanNotificationScheduler {

    /// Category identifier used by both the scheduler and AppDelegate.
    static let categoryID = "PLAN_BLOCK"

    private static let mainPrefix = "plan_block_"
    private static let prePrefix  = "plan_block_pre_"
    private static let snoozePrefix = "plan_block_snooze_"

    // MARK: - Public API

    /// Cancel + re-schedule notifications for a given DailyPlan. Safe to call
    /// after every plan regeneration; never produces duplicates.
    static func scheduleNotifications(for plan: DailyPlan) async {
        let center = UNUserNotificationCenter.current()

        // Only proceed if the user has actually granted us permission.
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }

        // Cancel anything we previously scheduled for this plan. MUST be
        // awaited — the old fire-and-forget `Task { ... }` version raced
        // with the subsequent `await scheduleStartAlert` loop and silently
        // removed the just-added requests when the cancel resolved second.
        await cancelNotifications(planID: plan.id)

        // Future blocks only — past blocks are noise.
        let now = Date()
        let blocks = (plan.blocks ?? []).filter { block in
            guard block.status != .done, block.status != .skipped else { return false }
            return block.startTime > now
        }

        for block in blocks {
            await scheduleStartAlert(for: block, planID: plan.id, center: center)
            if needsPreAlert(kind: block.kind) {
                await schedulePreAlert(for: block, planID: plan.id, center: center)
            }
        }
    }

    /// Cancel all notifications for a specific block. Called when the user
    /// marks a block done (or skips it) so the alert doesn't fire after the
    /// fact.
    static func cancelNotifications(planID: UUID, blockID: UUID) {
        let center = UNUserNotificationCenter.current()
        let prefixes = [
            "\(mainPrefix)\(planID.uuidString)_\(blockID.uuidString)",
            "\(prePrefix)\(planID.uuidString)_\(blockID.uuidString)",
            "\(snoozePrefix)\(planID.uuidString)_\(blockID.uuidString)"
        ]
        center.removePendingNotificationRequests(withIdentifiers: prefixes)
    }

    /// Cancel every notification we've scheduled for a given plan. Must be
    /// awaited so callers know the prior IDs are gone before adding new
    /// ones — otherwise the cancel can resolve after the new add and
    /// silently remove the requests we just installed.
    static func cancelNotifications(planID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let planSuffix = planID.uuidString
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map { $0.identifier }
            .filter {
                ($0.hasPrefix(mainPrefix) ||
                 $0.hasPrefix(prePrefix) ||
                 $0.hasPrefix(snoozePrefix))
                && $0.contains(planSuffix)
            }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Wipe the entire legacy ChecklistItem notification surface so we don't
    /// fire duplicates alongside the new plan-based system. Async so callers
    /// can await it before scheduling new plan-based requests.
    static func cancelLegacyChecklistNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix("task_reminder_") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Reschedule a single block's start alert in `minutes` minutes. Used by
    /// the Snooze action. Idempotent — overwrites any prior snooze.
    static func snooze(planID: UUID, block: PlanBlock, minutes: Int = 10) async {
        let center = UNUserNotificationCenter.current()
        let identifier = "\(snoozePrefix)\(planID.uuidString)_\(block.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = makeContent(for: block, title: "Snoozed reminder")
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger
        )
        try? await center.add(request)
    }

    // MARK: - Internals

    private static func scheduleStartAlert(
        for block: PlanBlock,
        planID: UUID,
        center: UNUserNotificationCenter
    ) async {
        let title = startTitle(for: block.kind)
        let content = makeContent(for: block, title: title)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents(for: block.startTime),
            repeats: false
        )
        let identifier = "\(mainPrefix)\(planID.uuidString)_\(block.id.uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger
        )
        try? await center.add(request)
    }

    private static func schedulePreAlert(
        for block: PlanBlock,
        planID: UUID,
        center: UNUserNotificationCenter
    ) async {
        let preTime = block.startTime.addingTimeInterval(-5 * 60)
        guard preTime > Date() else { return }  // already in the past

        let content = makeContent(
            for: block,
            title: preAlertTitle(for: block.kind),
            isPreAlert: true
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents(for: preTime),
            repeats: false
        )
        let identifier = "\(prePrefix)\(planID.uuidString)_\(block.id.uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger
        )
        try? await center.add(request)
    }

    private static func makeContent(
        for block: PlanBlock,
        title: String,
        isPreAlert: Bool = false
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = block.title
        if let detail = block.blockDescription, !detail.isEmpty {
            content.subtitle = detail
        }
        content.categoryIdentifier = categoryID
        content.sound = .default
        content.userInfo = [
            "planBlockID": block.id.uuidString,
            "planID": block.plan?.id.uuidString ?? "",
            "isPreAlert": isPreAlert
        ]
        // Threading lets iOS group multiple plan alerts together in
        // Notification Center per-day instead of stacking unboundedly.
        content.threadIdentifier = "plan_thread_\(Calendar.current.startOfDay(for: block.startTime).timeIntervalSince1970)"
        return content
    }

    private static func triggerComponents(for date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
    }

    // MARK: - Copy

    /// True when the kind benefits from a 5-minute heads-up.
    static func needsPreAlert(kind: TemplateBlock.Kind) -> Bool {
        switch kind {
        case .workout, .cardio, .deepWork, .meal, .windDown, .sleep: return true
        case .wake, .skincare, .supplement, .hydration, .caffeine,
             .rest, .mood, .routine:
            return false
        }
    }

    static func startTitle(for kind: TemplateBlock.Kind) -> String {
        switch kind {
        case .wake:       return "Good morning — start with water"
        case .skincare:   return "Skincare time"
        case .supplement: return "Supplement reminder"
        case .hydration:  return "Hydration check"
        case .meal:       return "Time to eat"
        case .caffeine:   return "Caffeine window"
        case .workout:    return "Workout — let's go"
        case .cardio:     return "Cardio time"
        case .deepWork:   return "Deep work — protect this block"
        case .rest:       return "Rest day"
        case .windDown:   return "Wind down"
        case .sleep:      return "Sleep target"
        case .mood:       return "Quick check-in"
        case .routine:    return "Plan reminder"
        }
    }

    static func preAlertTitle(for kind: TemplateBlock.Kind) -> String {
        switch kind {
        case .workout:  return "Workout in 5 minutes"
        case .cardio:   return "Cardio in 5 minutes"
        case .deepWork: return "Focus block in 5 minutes"
        case .meal:     return "Meal in 5 minutes"
        case .windDown: return "Wind down in 5 minutes"
        case .sleep:    return "Sleep target in 5 minutes"
        default:        return "Up next"
        }
    }
}
