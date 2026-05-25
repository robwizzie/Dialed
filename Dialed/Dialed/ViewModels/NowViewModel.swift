//
//  NowViewModel.swift
//  Dialed
//
//  Drives the NowView. Reads PersonalBaseline + latest SleepSession +
//  latest BiometricSnapshot + today's ContextEvents, runs them through
//  StateEngine, and synthesizes plan blocks from the legacy ChecklistItem
//  schedule until Phase 3's real planner replaces this.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class NowViewModel: ObservableObject {

    // MARK: - Published state

    @Published var recovery: StateEngine.ScoreBreakdown = .empty
    @Published var readiness: StateEngine.ScoreBreakdown = .empty
    @Published var energy: StateEngine.ScoreBreakdown = .empty
    @Published var strain: StateEngine.ScoreBreakdown = .empty

    @Published var nowBlock: PlanBlockPresentation?
    @Published var upcomingBlocks: [PlanBlockPresentation] = []

    @Published var greeting: String = "Hello"
    @Published var headerDateLine: String = ""

    /// Tint used by NowView's ambient background. Shifts through the day so
    /// the screen feels alive even without data updates.
    @Published var ambientLeftTint: Color = AppColors.Pillar.readiness.gradient.first!.opacity(0.55)
    @Published var ambientRightTint: Color = AppColors.Pillar.recovery.gradient.last!.opacity(0.45)

    // MARK: - Refresh

    func refresh(context: ModelContext) async {
        let now = Date()
        refreshHeader(now: now)
        refreshAmbient(now: now)

        // 1. Load the baseline, latest sleep, latest biometric.
        let baseline = latestBaseline(context: context)
        let lastSleep = latestSleep(context: context)
        let latestBio = latestBiometric(context: context)

        // 2. Today's load — pull from legacy DayLog so we don't depend on
        //    Phase 3 plumbing yet.
        let dayLog = todayLog(context: context)
        let dayLoad = StateEngine.DayLoadInputs(
            steps: dayLog?.steps ?? 0,
            activeCalories: dayLog?.activeEnergyBurned ?? 0,
            exerciseMinutes: dayLog?.exerciseMinutes ?? 0,
            workoutDurationMinutes: dayLog?.workoutDurationMinutes ?? 0,
            workoutIntensity: nil
        )

        // 3. Energy context — pull caffeine / meal / workout timing from
        //    today's ContextEvents.
        let energyCtx = buildEnergyContext(context: context, now: now)

        // 4. Run the engine.
        let inputs = StateEngine.LiveInputs(
            now: now,
            baseline: StateEngine.BaselineInputs.from(baseline),
            lastSleep: StateEngine.SleepInputs.from(lastSleep),
            latestBiometric: StateEngine.BiometricInputs.from(latestBio),
            dayLoad: dayLoad,
            energyContext: energyCtx
        )

        let recoveryResult = StateEngine.recovery(inputs)
        let strainResult = StateEngine.strain(inputs)
        let readinessResult = StateEngine.readiness(
            inputs,
            recoveryScore: recoveryResult.score,
            weeklyAdherence: weeklyAdherence(context: context),
            recentStrain: strainResult.score
        )
        let energyResult = StateEngine.energy(inputs, recoveryScore: recoveryResult.score)

        self.recovery = recoveryResult
        self.readiness = readinessResult
        self.energy = energyResult
        self.strain = strainResult

        // 5. Plan strip — synthesize from ChecklistItems until Phase 3.
        refreshPlanStrip(context: context, now: now)
    }

    // MARK: - Data fetchers

    private func latestBaseline(context: ModelContext) -> PersonalBaseline? {
        var desc = FetchDescriptor<PersonalBaseline>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first
    }

    private func latestSleep(context: ModelContext) -> SleepSession? {
        var desc = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first
    }

    private func latestBiometric(context: ModelContext) -> BiometricSnapshot? {
        var desc = FetchDescriptor<BiometricSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try? context.fetch(desc))?.first
    }

    private func todayLog(context: ModelContext) -> DayLog? {
        let today = Calendar.current.startOfDay(for: Date())
        let desc = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date == today }
        )
        return (try? context.fetch(desc))?.first
    }

    private func buildEnergyContext(context: ModelContext, now: Date) -> StateEngine.EnergyContext {
        let today = Calendar.current.startOfDay(for: now)
        let desc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate == today },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let events = (try? context.fetch(desc)) ?? []

        let lastCaffeine = events.first { $0.kindRaw == ContextEvent.Kind.caffeine.rawValue }
        let lastMeal = events.first { $0.kindRaw == ContextEvent.Kind.meal.rawValue }
        let lastWorkout = events.first { $0.kindRaw == ContextEvent.Kind.workout.rawValue }
        let lastEnergyRating = events.first { $0.kindRaw == ContextEvent.Kind.energy.rawValue }

        let minutesSince: (Date) -> Int = { Int(now.timeIntervalSince($0) / 60) }

        var activeMG: Double? = nil
        if let caf = lastCaffeine, let mg = caf.value {
            activeMG = StateEngine.activeCaffeine(doseMG: mg, dosedAt: caf.timestamp, now: now)
        }

        return StateEngine.EnergyContext(
            minutesSinceCaffeine: lastCaffeine.map { minutesSince($0.timestamp) },
            activeCaffeineMG: activeMG,
            minutesSinceMeal: lastMeal.map { minutesSince($0.timestamp) },
            minutesSinceWorkout: lastWorkout.map { minutesSince($0.timestamp) },
            selfReported: lastEnergyRating.flatMap { $0.value.map(Int.init) }
        )
    }

    private func weeklyAdherence(context: ModelContext) -> Double {
        // Use last 7 days of DayLog routine completion as a proxy for
        // adherence until the real Plan exists.
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return 0.7 }

        let desc = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date >= weekAgo },
            sortBy: [SortDescriptor(\.date)]
        )
        let logs = (try? context.fetch(desc)) ?? []
        guard !logs.isEmpty else { return 0.7 }

        let totals = logs.reduce(into: (done: 0, total: 0)) { acc, log in
            for item in (log.checklistItems ?? []) {
                acc.total += 1
                if item.checklistStatus == .done { acc.done += 1 }
            }
        }
        guard totals.total > 0 else { return 0.7 }
        return Double(totals.done) / Double(totals.total)
    }

    // MARK: - Plan strip synthesis

    /// Builds Now/Next blocks from ChecklistItems for today. Returns the most
    /// recent block whose time has passed as `nowBlock`, and the next 3 as
    /// upcoming. Phase 3 swaps this for real PlanBlocks.
    private func refreshPlanStrip(context: ModelContext, now: Date) {
        let today = Calendar.current.startOfDay(for: now)
        guard let log = todayLog(context: context) else {
            self.nowBlock = nil
            self.upcomingBlocks = []
            return
        }

        let items = (log.checklistItems ?? [])
        let blocks: [PlanBlockPresentation] = items.compactMap { item in
            guard let time = Calendar.current.date(
                bySettingHour: item.scheduledHour,
                minute: item.scheduledMinute,
                second: 0,
                of: today
            ) else { return nil }

            let pillar = pillarForChecklist(type: item.type, title: item.displayTitle)
            return PlanBlockPresentation(
                id: item.id,
                title: item.displayTitle,
                subtitle: item.displayDescription,
                time: time,
                icon: iconForChecklist(type: item.type, title: item.displayTitle),
                accent: pillar.gradient,
                isCurrent: false
            )
        }
        .sorted { $0.time < $1.time }

        let past = blocks.filter { $0.time <= now }
        let future = blocks.filter { $0.time > now }

        self.nowBlock = past.last.map {
            PlanBlockPresentation(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                time: $0.time,
                durationMinutes: 30,
                icon: $0.icon,
                accent: $0.accent,
                isCurrent: true
            )
        }
        self.upcomingBlocks = Array(future.prefix(3))
    }

    private func pillarForChecklist(type: String, title: String) -> AppColors.Pillar {
        let t = title.lowercased()
        if t.contains("workout") || t.contains("creatine") { return .strain }
        if t.contains("sleep") || t.contains("skincare") || t.contains("wind") { return .recovery }
        if t.contains("vitamin") || t.contains("supplement") || t.contains("lunch") || t.contains("meal") { return .energy }
        return .readiness
    }

    private func iconForChecklist(type: String, title: String) -> String {
        let t = title.lowercased()
        if t.contains("workout") { return "figure.strengthtraining.traditional" }
        if t.contains("creatine") || t.contains("supplement") { return "pills.fill" }
        if t.contains("vitamin") { return "pill.fill" }
        if t.contains("am") || t.contains("morning") { return "sun.max.fill" }
        if t.contains("pm") || t.contains("night") || t.contains("wind") { return "moon.stars.fill" }
        if t.contains("water") { return "drop.fill" }
        if t.contains("meal") || t.contains("lunch") || t.contains("dinner") { return "fork.knife" }
        return "checkmark.circle.fill"
    }

    // MARK: - Header / ambient

    private func refreshHeader(now: Date) {
        let hour = Calendar.current.component(.hour, from: now)
        let greetingWord: String
        switch hour {
        case 5..<12:  greetingWord = "Good morning"
        case 12..<17: greetingWord = "Good afternoon"
        case 17..<22: greetingWord = "Good evening"
        default:      greetingWord = "Up late?"
        }
        // First name only — pull from settings if present, otherwise neutral.
        let userName = UserSettings.load().firstName
        self.greeting = userName.isEmpty ? greetingWord : "\(greetingWord), \(userName)"

        let df = DateFormatter()
        df.dateFormat = "EEEE • MMM d"
        self.headerDateLine = df.string(from: now)
    }

    private func refreshAmbient(now: Date) {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<11:
            ambientLeftTint = AppColors.Pillar.energy.gradient.first!.opacity(0.55)
            ambientRightTint = AppColors.Pillar.readiness.gradient.last!.opacity(0.45)
        case 11..<17:
            ambientLeftTint = AppColors.Pillar.readiness.gradient.first!.opacity(0.5)
            ambientRightTint = AppColors.Pillar.energy.gradient.last!.opacity(0.4)
        case 17..<21:
            ambientLeftTint = AppColors.Pillar.strain.gradient.first!.opacity(0.4)
            ambientRightTint = AppColors.Pillar.energy.gradient.last!.opacity(0.35)
        default:
            ambientLeftTint = AppColors.Pillar.recovery.gradient.first!.opacity(0.45)
            ambientRightTint = AppColors.Pillar.readiness.gradient.last!.opacity(0.4)
        }
    }
}

// MARK: - Empty breakdown for first paint

extension StateEngine.ScoreBreakdown {
    static let empty = StateEngine.ScoreBreakdown(
        score: 0,
        grade: .poor,
        contributions: [],
        confidence: 0
    )
}

// MARK: - UserSettings convenience

private extension UserSettings {
    /// First name pulled from optional profile fields — falls back to empty
    /// so the greeting still reads cleanly.
    var firstName: String {
        // The legacy UserSettings doesn't have a first name field; we'll
        // pull it from a UserDefaults string Phase 6 onboarding will set.
        UserDefaults.standard.string(forKey: "user.firstName") ?? ""
    }
}
