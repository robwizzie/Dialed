//
//  GameService.swift
//  Dialed
//
//  Feeds quests, badges and the habit heatmap from the app's data and
//  keeps the score: which quests you finished (and their points), XP and
//  level, and the day each badge unlocked. New badges get a notification
//  and an in-app toast. Storage is UserDefaults JSON; the math lives in
//  HabitDays, QuestEngine and BadgeEngine.
//

import Foundation
import SwiftData
import HealthKit
import UserNotifications

// MARK: - Store

struct GameStore: Codable, Equatable {
    struct QuestDay: Codable, Equatable {
        /// Quest kind → points earned.
        var done: [String: Int] = [:]
        var claimed: Set<String> = []
        var swept = false
    }

    /// "yyyy-MM-dd" → that day's quests.
    var days: [String: QuestDay] = [:]
    /// Badge id → unlock date.
    var badges: [String: Date] = [:]
    /// Badges were evaluated at least once (the first run unlocks quietly).
    var badgesSeeded = false

    var xp: Int {
        days.values.reduce(0) { $0 + $1.done.values.reduce(0, +) + ($1.swept ? QuestEngine.sweepBonus : 0) }
    }
    var sweeps: Int { days.values.filter(\.swept).count }

    private static let key = "game.store"

    static func load() -> GameStore {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(GameStore.self, from: data) else { return GameStore() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

extension Notification.Name {
    /// userInfo["ids"]: [String] of badge ids just unlocked.
    static let badgesUnlocked = Notification.Name("BadgesUnlocked")
}

// MARK: - Service

@MainActor
enum GameService {

    struct QuestRow: Identifiable, Equatable {
        var quest: QuestEngine.Quest
        var status: QuestEngine.Status
        var id: String { quest.id }
    }

    struct Today: Equatable {
        var quests: [QuestRow] = []
        var level = QuestEngine.level(xp: 0)
        var xp = 0
        /// XP earned today (quests + sweep bonus).
        var xpToday = 0
    }

    // MARK: Quests

    static func today(context: ModelContext, now: Date = Date()) async -> Today {
        let calendar = Calendar.current
        // The big day (a wedding): no quests, nothing to miss.
        if EventModeStore.isEventDay(now, calendar: calendar) {
            let xp = GameStore.load().xp
            return Today(quests: [], level: QuestEngine.level(xp: xp), xp: xp, xpToday: 0)
        }
        let facts = await facts(context: context, now: now)
        let key = WeeklyReview.dayKey(now, calendar: calendar)
        var store = GameStore.load()
        var day = store.days[key] ?? GameStore.QuestDay()

        let quests = QuestEngine.today(now, facts: facts, calendar: calendar)
        let rows = quests.map { q -> QuestRow in
            let status = QuestEngine.status(q, facts: facts, claimed: day.claimed.contains(q.id), calendar: calendar)
            if status == .done, day.done[q.id] == nil { day.done[q.id] = q.points }
            // A quest that went done → missed (late snack) keeps its points; fair's fair.
            return QuestRow(quest: q, status: day.done[q.id] != nil ? .done : status)
        }
        if !rows.isEmpty, rows.allSatisfy({ $0.status == .done }) { day.swept = true }
        store.days[key] = day
        store.save()

        let xp = store.xp
        let todayXP = day.done.values.reduce(0, +) + (day.swept ? QuestEngine.sweepBonus : 0)
        return Today(quests: rows, level: QuestEngine.level(xp: xp), xp: xp, xpToday: todayXP)
    }

    /// Tap-to-claim for quests Dialed can't see.
    static func claim(_ quest: QuestEngine.Quest, now: Date = Date()) {
        let key = WeeklyReview.dayKey(now)
        var store = GameStore.load()
        var day = store.days[key] ?? GameStore.QuestDay()
        day.claimed.insert(quest.id)
        store.days[key] = day
        store.save()
    }

    static func facts(context: ModelContext, now: Date) async -> QuestEngine.Facts {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let settings = UserSettings.load()
        func at(_ hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today) ?? today }

        let health = HealthKitManager.shared
        async let hourlySteps = try? health.fetchHourlySums(.stepCount, unit: .count(), on: today)
        async let hourlyWater = try? health.fetchHourlySums(.dietaryWater, unit: .fluidOunceUS(), on: today)
        async let hourlyMiles = try? health.fetchHourlySums(.distanceWalkingRunning, unit: .mile(), on: today)
        let steps = await hourlySteps ?? []
        let water = await hourlyWater ?? []
        let miles = await hourlyMiles ?? []
        func sum(_ a: [Double], _ hours: Range<Int>) -> Double { hours.reduce(0) { $0 + ($1 < a.count ? a[$1] : 0) } }

        var f = QuestEngine.Facts(now: now)
        let foods = FoodLog.entries(on: today, context: context)
        f.proteinBefore11 = foods.filter { $0.time < at(11) }.reduce(0) { $0 + $1.protein }
        f.protein = foods.reduce(0) { $0 + $1.protein }
        f.calories = foods.reduce(0) { $0 + $1.calories }
        f.lastMealTime = foods.last?.time
        f.mealSlotsLogged = [foods.contains { $0.time < at(11) },
                             foods.contains { $0.time >= at(11) && $0.time < at(16) },
                             foods.contains { $0.time >= at(16) }].filter { $0 }.count
        f.proteinTarget = settings.proteinTargetGrams
        f.calorieBudget = (settings.calorieTarget ?? HomeViewModel.estimatedCutCalories(weight: settings.currentWeight))
            + (await EarnedCalories.day(now, context: context).earned)

        // Water: what you logged in Dialed, or Health's hourly total.
        let waterKind = ContextEvent.Kind.water.rawValue
        let waterEvents = ((try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.kindRaw == waterKind && $0.timestamp >= today }))) ?? [])
        let loggedWater = waterEvents.reduce(0) { $0 + ($1.value ?? 0) }
        let loggedBeforeNoon = waterEvents.filter { $0.timestamp < at(12) }.reduce(0) { $0 + ($1.value ?? 0) }
        f.waterOz = max(loggedWater, sum(water, 0..<24))
        f.waterBeforeNoonOz = max(loggedBeforeNoon, sum(water, 0..<12))
        f.waterTarget = settings.waterTargetOz

        f.steps = sum(steps, 0..<24)
        f.eveningSteps = sum(steps, 18..<21)
        let mileGoal = MileSettings.load().goalMiles
        f.mileGoal = mileGoal
        f.miles = max(sum(miles, 0..<24), MileHistory.load()?.milesByDay[today] ?? 0)
        f.milesBeforeNoon = sum(miles, 0..<12)

        let readings = await WeightDataSource.readings(context: context, since: today)
        f.weighInTime = readings.filter { calendar.isDate($0.date, inSameDayAs: today) }.map(\.date).min()

        let session = WorkoutPlanStore.session(on: today)
        f.isWorkoutDay = session.kind != .rest && session.kind != .event
        let doneKeys = WeeklyReview.workoutKeys(UserDefaults.standard.string(forKey: WorkoutPlanStore.doneKey) ?? "")
        f.workoutDone = doneKeys.contains(WeeklyReview.dayKey(today, calendar: calendar))

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            f.bedtime = WakeSchedule.load().bedtime(before: tomorrow, calendar: calendar)
        }
        return f
    }

    // MARK: Habit days

    /// The last `count` days, today included.
    static func habitDays(context: ModelContext, count: Int = 84, now: Date = Date()) async -> [HabitDays.Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let settings = UserSettings.load()
        let budget = settings.calorieTarget ?? HomeViewModel.estimatedCutCalories(weight: settings.currentWeight)
        let mileGoal = MileSettings.load().goalMiles
        let eventDate = GoalEvent.load()?.date

        let health = HealthKitManager.shared
        async let hkEnergy = try? health.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: count)
        async let hkProtein = try? health.fetchDailySums(.dietaryProtein, unit: .gram(), days: count)
        async let hkWater = try? health.fetchDailySums(.dietaryWater, unit: .fluidOunceUS(), days: count)
        let readings = await WeightDataSource.readings(context: context, since: start)
        let energy = await hkEnergy ?? [:], protein = await hkProtein ?? [:], water = await hkWater ?? [:]

        let logs = (try? context.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < end }))) ?? []
        let workoutLogs = (try? context.fetch(FetchDescriptor<PlanWorkoutLog>(
            predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        let doneKeys = WeeklyReview.workoutKeys(UserDefaults.standard.string(forKey: WorkoutPlanStore.doneKey) ?? "")
        let milesByDay = MileHistory.load()?.milesByDay ?? [:]
        let workoutDays = Set(workoutLogs.map { calendar.startOfDay(for: $0.date) })
        let weighIns = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.date) }
        let waterKind = ContextEvent.Kind.water.rawValue
        let workoutKind = ContextEvent.Kind.workout.rawValue

        return WeeklyReview.days(from: start, to: today, calendar: calendar).map { d in
            let log = logs.first { calendar.isDate($0.date, inSameDayAs: d) }
            let dayEvents = events.filter { calendar.isDate($0.logicalDate, inSameDayAs: d) }
            let foods = FoodLog.entries(on: d, context: context)
            var day = HabitDays.Day(date: d)
            day.foodEntries = foods.count
            day.calories = max(foods.reduce(0) { $0 + $1.calories }, energy[d] ?? 0)
            day.protein = max(foods.reduce(0) { $0 + $1.protein }, protein[d] ?? 0)
            let loggedWater = (log?.waterOz ?? 0) + dayEvents.filter { $0.kindRaw == waterKind }.reduce(0) { $0 + ($1.value ?? 0) }
            day.waterOz = max(loggedWater, water[d] ?? 0)
            day.miles = milesByDay[d] ?? 0
            day.workout = workoutDays.contains(d) || doneKeys.contains(WeeklyReview.dayKey(d, calendar: calendar))
                || dayEvents.contains { $0.kindRaw == workoutKind }
            day.weighInTime = weighIns[d]?.map(\.date).min()
            day.weighedIn = day.weighInTime != nil
            day.mileGoal = mileGoal
            day.proteinTarget = settings.proteinTargetGrams
            day.waterTarget = settings.waterTargetOz
            day.calorieBudget = budget
            day.exempt = EventMode.isEventDay(event: eventDate, on: d, calendar: calendar)
            return day
        }
    }

    // MARK: Badges

    /// Evaluates every badge, records new unlocks, and announces them
    /// (notification + toast) — except on the very first run, which just
    /// catches up quietly.
    static func badges(context: ModelContext, days: [HabitDays.Day]? = nil, now: Date = Date()) async -> [BadgeEngine.Status] {
        let calendar = Calendar.current
        var history = days ?? []
        if days == nil { history = await habitDays(context: context, count: 120, now: now) }
        var store = GameStore.load()

        // Trend weight lost: from the challenge start, else your heaviest recent trend.
        let since = calendar.date(byAdding: .day, value: -180, to: now) ?? now
        let readings = await WeightDataSource.readings(context: context, since: since)
        let series = WeightChallengeEngine.dailySeries(readings, calendar: calendar)
        let challenge = WeightChallenge.load()
        var lost = 0.0
        if let latest = series.last {
            let start = challenge.flatMap { c in
                c.startWeightOverride ?? series.first(where: { $0.day >= calendar.startOfDay(for: c.startDate) })?.trend
            } ?? series.map(\.trend).max() ?? latest.trend
            lost = max(0, start - latest.trend)
        }

        // Personal records, session by session.
        let sets = PlanWorkoutLogStore.allSets(context: context).filter(\.completed)
            .map { StrengthMilestones.SetRecord(exercise: $0.exerciseName, date: $0.date, weight: $0.weightLbs, reps: $0.reps) }
        let sessions = Dictionary(grouping: sets) { calendar.startOfDay(for: $0.date) }
        let prCount = sessions.keys.sorted().reduce(0) { total, day in
            total + StrengthMilestones.prs(session: sessions[day] ?? [], history: sets.filter { $0.date < day }).count
        }

        let workoutKind = ContextEvent.Kind.workout.rawValue, fun = FunActivityService.subtype
        let funCount = (try? context.fetchCount(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.kindRaw == workoutKind && $0.subtype == fun }))) ?? 0

        var leading = 0
        if let c = challenge, let yourStart = c.startWeightOverride ?? series.first(where: { $0.day >= calendar.startOfDay(for: c.startDate) })?.pounds,
           let friendStart = c.friendStartWeight ?? c.friendWeighIns.min(by: { $0.date < $1.date })?.pounds {
            leading = BadgeEngine.longestLead(
                yours: series.map { ($0.day, $0.pounds) }, yourStart: yourStart,
                friend: c.friendWeighIns.map { (calendar.startOfDay(for: $0.date), $0.pounds) }, friendStart: friendStart,
                percent: c.scoring == .percent, from: c.startDate, to: min(now, c.endDate), calendar: calendar)
        }

        let mileHistory = MileHistory.load()
        let mileGoal = MileSettings.load().goalMiles
        let inputs = BadgeEngine.Inputs(
            days: history, today: now, lostByTrend: lost,
            bestMileStreak: mileHistory?.longestStreak(goal: mileGoal, calendar: calendar) ?? 0,
            totalMiles: mileHistory?.days.reduce(0) { $0 + $1.miles } ?? 0,
            prCount: prCount, funActivities: funCount, daysLeading: leading,
            level: QuestEngine.level(xp: store.xp).number, questSweeps: store.sweeps)
        let statuses = BadgeEngine.evaluate(inputs, calendar: calendar)

        let fresh = statuses.filter { $0.unlocked && store.badges[$0.badge.id] == nil }
        for s in fresh { store.badges[s.badge.id] = now }
        let announce = store.badgesSeeded && !fresh.isEmpty
        store.badgesSeeded = true
        store.save()
        if announce {
            NotificationCenter.default.post(name: .badgesUnlocked, object: nil, userInfo: ["ids": fresh.map(\.badge.id)])
            await notify(fresh.map(\.badge))
        }
        return statuses
    }

    static func unlockDate(_ id: String) -> Date? { GameStore.load().badges[id] }

    private static func notify(_ badges: [BadgeEngine.Badge]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              let first = badges.first else { return }
        let content = UNMutableNotificationContent()
        content.title = badges.count == 1 ? "🏅 Badge unlocked: \(first.title)" : "🏅 \(badges.count) badges unlocked"
        content.body = badges.count == 1 ? first.detail : badges.map(\.title).joined(separator: ", ")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "badge_\(first.id)_\(Int(Date().timeIntervalSince1970))",
                                            content: content, trigger: nil)
        try? await center.add(request)
    }
}
