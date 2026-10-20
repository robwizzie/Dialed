//
//  SkincareCleanup.swift
//  Dialed
//
//  One-time removal of skincare / face-wash tasks from data saved before
//  they were dropped: template blocks, today's and future plan blocks
//  (and their notifications), today's and future checklist items, custom
//  routine tasks, checklist reminder settings, and any pending reminder
//  that mentions them. Past days keep their history. Idempotent; runs at
//  launch next to the legacy migration.
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
enum SkincareCleanup {
    static let doneKey = "cleanup.skincare.v1"

    static func runIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        let today = Calendar.current.startOfDay(for: Date())

        // Weekly template blocks — the source of every future plan.
        for block in (try? context.fetch(FetchDescriptor<TemplateBlock>())) ?? []
        where SkincareMatcher.isSkincare(kindRaw: block.kindRaw, title: block.title, detail: block.blockDescription) {
            context.delete(block)
        }

        // Today's and future plan blocks, with their notifications.
        for block in (try? context.fetch(FetchDescriptor<PlanBlock>(predicate: #Predicate { $0.startTime >= today }))) ?? []
        where SkincareMatcher.isSkincare(kindRaw: block.kindRaw, title: block.title, detail: block.blockDescription) {
            if let planID = block.plan?.id {
                PlanNotificationScheduler.cancelNotifications(planID: planID, blockID: block.id)
            }
            context.delete(block)
        }

        // Today's and future checklist items.
        for item in (try? context.fetch(FetchDescriptor<ChecklistItem>(predicate: #Predicate { $0.dayDate >= today }))) ?? []
        where SkincareMatcher.isSkincare(checklistType: item.type, customTitle: item.customTitle,
                                         customDescription: item.customDescription) {
            context.delete(item)
        }
        try? context.save()

        // Custom routine tasks (UserDefaults JSON).
        let routineKey = "routineTaskTemplates"
        if let data = defaults.data(forKey: routineKey),
           let templates = try? JSONDecoder().decode([RoutineTaskTemplate].self, from: data) {
            let kept = templates.filter { !SkincareMatcher.matches($0.title) && !SkincareMatcher.matches($0.description) }
            if kept.count != templates.count, let encoded = try? JSONEncoder().encode(kept) {
                defaults.set(encoded, forKey: routineKey)
            }
        }

        // Checklist reminder settings.
        var settings = UserSettings.load()
        let enabled = settings.enabledNotifications.subtracting(SkincareMatcher.checklistTypes)
        if enabled != settings.enabledNotifications || settings.customChecklistTimes?.keys.contains(where: SkincareMatcher.checklistTypes.contains) == true {
            settings.enabledNotifications = enabled
            settings.customChecklistTimes = settings.customChecklistTimes?.filter { !SkincareMatcher.checklistTypes.contains($0.key) }
            settings.save()
        }

        defaults.set(true, forKey: doneKey)
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)

        // Anything still pending that mentions skincare.
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let ids = pending.filter {
                SkincareMatcher.matches($0.identifier) || SkincareMatcher.matches($0.content.title)
                    || SkincareMatcher.matches($0.content.body)
            }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
