//
//  DayRecapStore.swift
//  Dialed
//
//  A past day for Home, loaded piece by piece. What the app keeps itself
//  (food, water, the mile, the logged workout, quests, that morning's
//  scores, the night's sleep) shows at once; each Health or Google source
//  then fills in on its own, with a time limit, so one slow source never
//  holds up the rest. Everything is for the chosen day — no "today" values
//  leak in. Results are cached per day and dropped when data changes.
//

import Foundation
import SwiftData
import HealthKit

@MainActor
final class DayRecapStore: ObservableObject {
    static let shared = DayRecapStore()

    struct Pillars: Equatable {
        var recovery: Int?
        var readiness: Int?
        var strain: Int?
    }

    struct Moment: Identifiable, Equatable {
        var id: String
        var name: String
        var start: Date
        var minutes: Double
        var calories: Double?
    }

    enum Part: Hashable { case health, watch, earned, activity, weight }

    struct Day: Equatable {
        // From the app's own data — always there.
        var calories: Double = 0
        var protein: Double = 0
        var waterOz: Double = 0
        var calorieTarget: Double = 0
        var proteinTarget: Double = 0
        var waterTarget: Double = 0
        var miles: Double?
        var steps: Double?
        var pillars: Pillars?
        var night: HealthInsights.Night?
        var workoutTitle: String?
        var setsDone = 0
        var quests: (done: Int, xp: Int)?
        // From Health / the watch — nil until loaded.
        var watch: [DetectedWorkout]?
        var earned: EarnedCalories.Day?
        var moments: [Moment]?
        var suggestions: [DaySuggestions.Item]?
        var weighIn: Double??
        var loaded: Set<Part> = []
        var failed: Set<Part> = []
        var loadedAt = Date.distantPast

        static func == (a: Day, b: Day) -> Bool {
            a.calories == b.calories && a.protein == b.protein && a.waterOz == b.waterOz && a.miles == b.miles
                && a.steps == b.steps && a.pillars == b.pillars && a.night == b.night && a.workoutTitle == b.workoutTitle
                && a.setsDone == b.setsDone && a.quests?.done == b.quests?.done && a.quests?.xp == b.quests?.xp
                && a.watch == b.watch && a.earned == b.earned && a.moments == b.moments && a.suggestions == b.suggestions
                && a.weighIn == b.weighIn && a.loaded == b.loaded && a.failed == b.failed
        }
    }

    @Published private(set) var days: [String: Day] = [:]
    /// Bumped when cached days are dropped, so the open day reloads.
    @Published private(set) var version = 0

    private var running: [String: Task<Void, Never>] = [:]
    private let calendar = Calendar.current
    private let timeout: Double = 8

    private init() {
        NotificationCenter.default.addObserver(forName: .dialedDataDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.invalidate() }
        }
    }

    func day(_ date: Date) -> Day? { days[DayLoadKit.key(date)] }

    /// Forget every cached day (something was logged, named or dismissed).
    func invalidate() {
        for task in running.values { task.cancel() }
        running = [:]
        days = [:]
        version += 1
    }

    /// Loads `date` unless a fresh copy is cached. Safe to call repeatedly:
    /// a load already running for the day is joined, not repeated.
    func load(_ date: Date, context: ModelContext, force: Bool = false) async {
        let start = calendar.startOfDay(for: date)
        let key = DayLoadKit.key(start)
        if !force, let cached = days[key], Date().timeIntervalSince(cached.loadedAt) < 5 * 60 { return }
        if !force, let task = running[key] {
            await task.value
            return
        }
        running[key]?.cancel()
        let task = Task { await self.fill(start, key: key, context: context) }
        running[key] = task
        await task.value
        if running[key] == task { running[key] = nil }
    }

    // MARK: - Filling

    private func fill(_ start: Date, key: String, context: ModelContext) async {
        var local = localDay(start, context: context)
        local.loadedAt = Date()
        days[key] = local

        let back = max(0, calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: Date())).day ?? 0)
        let timeout = self.timeout

        await withTaskGroup(of: (Part, Bool).self) { group in
            group.addTask { @MainActor in
                let sums = await DayLoadKit.withTimeout(seconds: timeout) { await self.healthSums(start, back: back) }
                if let sums { self.update(key) { $0.applyHealth(sums) } }
                return (.health, sums != nil)
            }
            group.addTask { @MainActor in
                let watch = await DayLoadKit.withTimeout(seconds: timeout) { await WorkoutDetector.workouts(on: start, context: context) }
                self.update(key) { $0.watch = watch ?? [] }
                return (.watch, watch != nil)
            }
            group.addTask { @MainActor in
                let earned = await DayLoadKit.withTimeout(seconds: timeout + 4) { await EarnedCalories.day(start, context: context) }
                self.update(key) { $0.earned = earned ?? EarnedCalories.Day() }
                return (.earned, earned != nil)
            }
            group.addTask { @MainActor in
                let active = await DayLoadKit.withTimeout(seconds: timeout + 4) { await FunActivityService.day(start, context: context) }
                self.update(key) { d in
                    d.moments = (active?.logged ?? []).map {
                        Moment(id: "\($0.id)", name: $0.text ?? "Activity", start: $0.timestamp,
                               minutes: $0.value ?? 0, calories: $0.secondaryValue)
                    }
                }
                // Suggestions need the watch sessions too; fetch them here
                // (cached by the watch part's own call shortly after).
                if let active {
                    let workouts = await DayLoadKit.withTimeout(seconds: timeout) { await WorkoutDetector.workouts(on: start, context: context) } ?? []
                    let items = RecentSuggestions.pending(on: start, bouts: active.unnamed, workouts: workouts, context: context)
                    self.update(key) { $0.suggestions = items }
                } else {
                    self.update(key) { $0.suggestions = [] }
                }
                return (.activity, active != nil)
            }
            group.addTask { @MainActor in
                let end = self.calendar.date(byAdding: .day, value: 1, to: start) ?? start
                let readings = await DayLoadKit.withTimeout(seconds: timeout) {
                    await WeightDataSource.readings(context: context, since: start)
                }
                let first = readings?.filter { $0.date >= start && $0.date < end }.min { $0.date < $1.date }
                self.update(key) { $0.weighIn = .some(first?.pounds) }
                return (.weight, readings != nil)
            }
            for await (part, ok) in group {
                update(key) { d in
                    d.loaded.insert(part)
                    if !ok { d.failed.insert(part) }
                }
            }
        }
    }

    private func update(_ key: String, _ change: (inout Day) -> Void) {
        guard var d = days[key] else { return }
        change(&d)
        days[key] = d
    }

    // MARK: - The app's own data

    private func localDay(_ start: Date, context: ModelContext) -> Day {
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let settings = UserSettings.load()
        var d = Day()

        let foods = FoodLog.entries(on: start, context: context)
        d.calories = foods.reduce(0) { $0 + $1.calories }
        d.protein = foods.reduce(0) { $0 + $1.protein }

        let water = ContextEvent.Kind.water.rawValue
        let waterEvents = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.kindRaw == water && $0.logicalDate >= start && $0.logicalDate < end }))) ?? []
        let log = (try? context.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.date >= start && $0.date < end })))?.first
        d.waterOz = (log?.waterOz ?? 0) + waterEvents.reduce(0) { $0 + ($1.value ?? 0) }
        d.steps = log?.steps.map(Double.init)

        d.calorieTarget = CalorieTarget.current(settings: settings, weight: settings.currentWeight, now: start)
        d.proteinTarget = settings.proteinTargetGrams
        d.waterTarget = settings.waterTargetOz
        d.miles = MileHistory.load()?.day(start)?.miles

        // That day's stored scores, not today's live ones.
        if let s = (try? context.fetch(FetchDescriptor<DailyScoreSnapshot>(predicate: #Predicate { $0.logicalDate == start })))?.first {
            d.pillars = Pillars(recovery: s.recoveryScore, readiness: s.readinessScore,
                                strain: s.strainScore.flatMap { $0 > 0 ? $0 : nil })
        }

        // The night that ended that morning.
        let sessions = (try? context.fetch(FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < end }))) ?? []
        d.night = HealthInsights.combine(sessions.map { s in
            HealthInsights.Night(
                wakeDay: start, bedtime: s.startTime, wakeTime: s.endTime,
                inBedMinutes: s.inBedMinutes, asleepMinutes: s.asleepMinutes,
                deepMinutes: s.deepMinutes, remMinutes: s.remMinutes, lightMinutes: s.lightMinutes,
                awakeMinutes: s.awakeMinutes, awakenings: s.awakeningCount, vendorScore: s.vendorSleepScore,
                segments: s.stageTimeline)
        })

        if let workout = PlanWorkoutLogStore.log(for: WorkoutPlanStore.key(start), context: context) {
            d.workoutTitle = workout.title
            d.setsDone = PlanWorkoutLogStore.sets(for: workout.id, context: context).filter(\.completed).count
        }
        if let q = GameStore.load().days[WeeklyReview.dayKey(start)], !q.done.isEmpty {
            d.quests = (q.done.count, q.done.values.reduce(0, +) + (q.swept ? QuestEngine.sweepBonus : 0))
        }
        return d
    }

    // MARK: - Health totals for that one day

    struct HealthSums: Equatable {
        var calories: Double?
        var protein: Double?
        var waterOz: Double?
        var steps: Double?
    }

    /// Daily sums (one statistics query each) for the day `back` days ago.
    private func healthSums(_ start: Date, back: Int) async -> HealthSums {
        let health = HealthKitManager.shared
        let days = back + 1
        async let cal = try? health.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: days)
        async let pro = try? health.fetchDailySums(.dietaryProtein, unit: .gram(), days: days)
        async let water = try? health.fetchDailySums(.dietaryWater, unit: .fluidOunceUS(), days: days)
        async let steps = try? health.fetchDailySums(.stepCount, unit: .count(), days: days)
        return HealthSums(calories: await cal?[start], protein: await pro?[start],
                          waterOz: await water?[start], steps: await steps?[start])
    }
}

private extension DayRecapStore.Day {
    /// Health's totals fill in what the app didn't log (never double-count:
    /// the larger of the two, like Home does for today).
    mutating func applyHealth(_ s: DayRecapStore.HealthSums) {
        calories = max(calories, s.calories ?? 0)
        protein = max(protein, s.protein ?? 0)
        waterOz = max(waterOz, s.waterOz ?? 0)
        if let st = s.steps { steps = max(steps ?? 0, st) }
    }
}
