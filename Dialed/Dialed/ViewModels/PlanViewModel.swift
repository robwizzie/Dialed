//
//  PlanViewModel.swift
//  Dialed
//
//  Drives PlanView. Loads (or generates) a DailyPlan for the selected date,
//  groups its blocks into human day periods, and exposes display-ready value
//  types so the view stays render-only.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class PlanViewModel: ObservableObject {

    // MARK: - Published state

    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var weekDays: [Date] = []
    @Published var groupedBlocks: [DayPeriodGroup] = []

    @Published var wakeAnchorLabel: String = "—"
    @Published var sleepAnchorLabel: String = "—"
    @Published var recoveryLabel: String = "—"

    // MARK: - Display value types

    struct BlockItem: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String?
        let icon: String
        let pillar: AppColors.Pillar
        let startTime: Date
        let durationMinutes: Int
        let status: PlanBlock.Status
        let skipReason: String?

        var timeLabel: String {
            Self.timeFormatter.string(from: startTime)
        }

        var durationLabel: String? {
            guard durationMinutes > 0 else { return nil }
            if durationMinutes >= 60 {
                let h = durationMinutes / 60
                let m = durationMinutes % 60
                return m == 0 ? "\(h)h" : "\(h)h \(m)m"
            }
            return "\(durationMinutes)m"
        }

        private static let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f
        }()
    }

    struct DayPeriodGroup {
        let title: String
        let icon: String
        let timeRange: String
        let blocks: [BlockItem]
    }

    // MARK: - Refresh

    /// Initial load — picks today, builds the week strip, generates a plan
    /// if needed.
    func refresh(context: ModelContext) async {
        rebuildWeekStrip(around: selectedDate)
        await loadOrGenerate(for: selectedDate, context: context)
    }

    /// User tapped a different day in the strip.
    func select(date: Date, context: ModelContext) async {
        selectedDate = Calendar.current.startOfDay(for: date)
        rebuildWeekStrip(around: selectedDate)
        await loadOrGenerate(for: selectedDate, context: context)
    }

    /// Force re-run PlanGenerator (useful after editing the template, or
    /// after a recovery update mid-day).
    func regenerate(context: ModelContext) async {
        await generatePlan(for: selectedDate, context: context)
        await loadOrGenerate(for: selectedDate, context: context)
    }

    /// Toggle a block's completion state. Round-tripping the status writes
    /// a ContextEvent for the Timeline.
    func toggle(blockID: UUID, context: ModelContext) async {
        let desc = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.id == blockID }
        )
        guard let block = (try? context.fetch(desc))?.first else { return }

        switch block.status {
        case .upcoming, .active, .due:
            block.markDone()
            // Drop a routineTask event on the Timeline for adherence stats.
            let event = ContextEvent(
                timestamp: Date(),
                kind: .routineTask,
                subtype: block.kindRaw,
                text: block.title,
                source: .manual
            )
            context.insert(event)
            block.producedEventID = event.id
        case .done:
            block.status = .upcoming
            block.completedAt = nil
            block.updatedAt = Date()
            if let eventID = block.producedEventID {
                let evDesc = FetchDescriptor<ContextEvent>(
                    predicate: #Predicate { $0.id == eventID }
                )
                if let ev = (try? context.fetch(evDesc))?.first {
                    context.delete(ev)
                }
                block.producedEventID = nil
            }
        case .skipped:
            block.status = .upcoming
            block.skippedReason = nil
            block.updatedAt = Date()
        }

        try? context.save()
        await loadOrGenerate(for: selectedDate, context: context)
    }

    // MARK: - Internals

    private func rebuildWeekStrip(around date: Date) {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)  // 1 = Sun
        guard let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: date) else {
            weekDays = [date]; return
        }
        weekDays = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start))
        }
    }

    private func loadOrGenerate(for date: Date, context: ModelContext) async {
        let dayStart = Calendar.current.startOfDay(for: date)
        let desc = FetchDescriptor<DailyPlan>(
            predicate: #Predicate { $0.date == dayStart }
        )
        var plan = (try? context.fetch(desc))?.first

        if plan == nil {
            await generatePlan(for: date, context: context)
            plan = (try? context.fetch(desc))?.first
        }

        guard let plan else {
            groupedBlocks = []
            wakeAnchorLabel = "—"
            sleepAnchorLabel = "—"
            recoveryLabel = "—"
            return
        }

        rebuildDisplay(from: plan)
    }

    private func generatePlan(for date: Date, context: ModelContext) async {
        // Find (or seed) the active template.
        let templateDesc = FetchDescriptor<WeeklyTemplate>(
            predicate: #Predicate { $0.isActive == true }
        )
        let template: WeeklyTemplate = (try? context.fetch(templateDesc))?.first
            ?? WeeklyTemplate.seedDefault(into: context)

        // Pull baseline for default wake/sleep anchors and the latest
        // recovery for the auto-skip filter.
        var baselineDesc = FetchDescriptor<PersonalBaseline>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        baselineDesc.fetchLimit = 1
        let baseline = (try? context.fetch(baselineDesc))?.first

        let wake = PlanGenerator.defaultWakeTime(for: date, baseline: baseline)
        let sleep = PlanGenerator.defaultSleepTime(for: date, baseline: baseline)

        // Get recovery from the NowView state if it's been computed today.
        var bioDesc = FetchDescriptor<BiometricSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        bioDesc.fetchLimit = 1
        let latestBio = (try? context.fetch(bioDesc))?.first
        var sleepDesc = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        sleepDesc.fetchLimit = 1
        let latestSleep = (try? context.fetch(sleepDesc))?.first

        let recoveryInputs = StateEngine.LiveInputs(
            now: Date(),
            baseline: StateEngine.BaselineInputs.from(baseline),
            lastSleep: StateEngine.SleepInputs.from(latestSleep),
            latestBiometric: StateEngine.BiometricInputs.from(latestBio)
        )
        let recovery = StateEngine.recovery(recoveryInputs)
        let readiness = StateEngine.readiness(recoveryInputs, recoveryScore: recovery.score)

        let inputs = PlanGenerator.Inputs(
            date: date,
            template: template,
            wakeTime: wake,
            sleepTargetTime: sleep,
            recoveryScore: recovery.score,
            readinessScore: readiness.score
        )

        _ = try? PlanGenerator.generatePlan(inputs: inputs, context: context)
        try? context.save()
    }

    private func rebuildDisplay(from plan: DailyPlan) {
        let blocks = (plan.blocks ?? []).sorted { $0.startTime < $1.startTime }

        let items: [BlockItem] = blocks.map { b in
            BlockItem(
                id: b.id,
                title: b.title,
                subtitle: b.blockDescription,
                icon: b.kind.defaultIcon,
                pillar: b.kind.defaultPillar,
                startTime: b.startTime,
                durationMinutes: b.durationMinutes,
                status: b.liveStatus(),
                skipReason: b.skippedReason
            )
        }

        let grouped = group(items)
        self.groupedBlocks = grouped

        // Anchor labels
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        self.wakeAnchorLabel = plan.anchorWakeTime.map(f.string(from:)) ?? "—"
        self.sleepAnchorLabel = plan.anchorSleepTime.map(f.string(from:)) ?? "—"
        if let rec = plan.generationRecovery {
            self.recoveryLabel = "\(rec)/100"
        } else {
            self.recoveryLabel = "—"
        }
    }

    private func group(_ items: [BlockItem]) -> [DayPeriodGroup] {
        let calendar = Calendar.current

        let buckets: [(String, String, ClosedRange<Int>)] = [
            ("Morning",   "sunrise.fill",      5...10),
            ("Midday",    "sun.max.fill",     11...13),
            ("Afternoon", "sun.haze.fill",    14...17),
            ("Evening",   "sunset.fill",      18...20),
            ("Night",     "moon.stars.fill",  21...28)   // 21–28 = up to 4 AM next day
        ]

        var groups: [DayPeriodGroup] = []
        for (title, icon, range) in buckets {
            let blocks = items.filter {
                var h = calendar.component(.hour, from: $0.startTime)
                if h < 5 { h += 24 }  // wrap 0–4 AM into "Night"
                return range.contains(h)
            }
            guard !blocks.isEmpty else { continue }

            let timeRange = Self.rangeLabel(for: range)
            groups.append(DayPeriodGroup(title: title, icon: icon, timeRange: timeRange, blocks: blocks))
        }
        return groups
    }

    private static func rangeLabel(for range: ClosedRange<Int>) -> String {
        let lower = range.lowerBound
        let upper = range.upperBound > 24 ? range.upperBound - 24 : range.upperBound
        let formattedLower = format12(lower)
        let formattedUpper = format12(upper)
        return "\(formattedLower) – \(formattedUpper)"
    }

    private static func format12(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12 AM" }
        if h == 12 { return "12 PM" }
        return h > 12 ? "\(h - 12) PM" : "\(h) AM"
    }
}
