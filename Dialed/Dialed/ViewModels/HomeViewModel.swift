//
//  HomeViewModel.swift
//  Dialed
//
//  Drives the Neka-style Home tab. Pulls from every source you own and
//  merges them into one picture:
//
//    • Pixel Watch → Google Health API (sleep, HRV, resting HR, SpO2,
//      breathing, heart rate, steps) via GoogleHealthSyncService
//    • Smart scale → Apple Health body mass and/or Google Health weight,
//      plus manual weigh-ins (WeightEntry)
//    • WaterH bottle → Apple Health dietary water (and/or Google Health
//      hydration), plus quick-captured water (ContextEvent)
//    • Everything Dialed already stores (DayLog, plan, food, sleep)
//
//  Every source is optional. A missing permission or a disconnected
//  device just leaves that tile in its empty state.
//

import Foundation
import SwiftData
import SwiftUI

struct HomeTimelineItem: Identifiable, Equatable {
    enum Status: Equatable {
        case done, active, upcoming, missed

        var label: String {
            switch self {
            case .done:     return "Completed"
            case .active:   return "In progress"
            case .upcoming: return "Upcoming"
            case .missed:   return "Missed"
            }
        }
    }

    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let status: Status
    let tint: Color
}

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Header

    @Published var firstName: String = ""
    @Published var dateLine: String = ""

    // MARK: - Hero callouts

    @Published var heartRate: Double?
    @Published var heartRateIsLive = false
    @Published var breathingRate: Double?
    @Published var spO2: Double?

    // MARK: - Weight & challenge

    @Published var weightReadings: [WeightReading] = []
    @Published var latestWeight: WeightReading?
    @Published var challenge: WeightChallenge?
    @Published var progress: WeightChallengeEngine.Progress?
    /// "You need 1.3 lb/week to beat Dave" — refreshed every 10 minutes at most.
    @Published var race: RacePace.Report?
    private var raceCheckedAt: Date?
    /// Your usual calorie target while final push has tightened it (nil otherwise).
    @Published var finalPushUsualTarget: Double?
    /// The challenge end the final-push notifications were last built for.
    private var finalPushScheduledFor: Date??

    // MARK: - Tiles

    @Published var waterOz: Double = 0
    @Published var waterTargetOz: Double = 120
    @Published var waterWeek: [Double] = []

    @Published var hrv: Double?
    @Published var hrvSeries: [Double] = []
    @Published var hrvBaseline: Double?

    @Published var sleepHours: Double?
    @Published var sleepSeries: [Double] = []

    @Published var restingHR: Double?

    @Published var steps: Int = 0
    @Published var stepsSeries: [Int] = []
    /// The daily mile (walked or run): today, the last 7 days, the streak.
    @Published var milesToday: Double = 0
    @Published var milesWeek: [Double] = []
    @Published var mileStreak: Int = 0
    @Published var ranToday = false
    @Published var mileGoal: Double = 1
    /// Steps per mile used for step-only days (manual, learned or default).
    @Published var stepsPerMileInUse: Double = MileSettings.defaultStepsPerMile
    let stepGoal = 10_000

    @Published var proteinGrams: Double = 0
    @Published var proteinTarget: Double = 190
    @Published var caloriesIn: Double = 0
    @Published var calorieTarget: Double = 2_200
    /// Calories every workout and activity burned today (added to the budget on screen).
    @Published var earned = EarnedCalories.Day()
    /// What you can eat today: the target plus what you've earned.
    var calorieBudget: Double { calorieTarget + earned.earned }

    // MARK: - Timeline & coach

    @Published var timeline: [HomeTimelineItem] = []
    @Published var insights: [CoachInsight] = []

    // MARK: - Device freshness

    @Published var lastWatchSync: Date?
    @Published var lastWaterReading: Date?
    @Published var isRefreshing = false

    /// Today in one value — fed to Apple Intelligence and the fallbacks.
    @Published var snapshot = HealthSnapshot()

    /// Today's mood for your avatar, and what would move it up.
    @Published var moodReading: AvatarMood.Reading?
    /// The day you're working toward, and where your trend lands you then.
    @Published var goalEvent: GoalEvent?
    @Published var goalProjection: WeightChallengeEngine.Projection?
    /// "If every day were like…" — see PathProjection.
    @Published var pathScenarios: [PathProjection.Scenario] = []
    /// The date those scenarios project to (goal day, or 30 days out).
    @Published var pathTargetDate: Date?
    private var pathDays: [PathProjection.DayRecord] = []
    private var currentWeightForPaths: Double = 0

    private let health = HealthKitManager.shared
    private var watchConnected: Bool { GoogleHealthSyncService.isConnected }
    // v2: re-pull two weeks once for sleep stage timelines + skin temperature.
    private static let backfillKey = "home.googleHealthBackfilled.v2"
    private static let lastWatchSyncKey = "home.lastGoogleHealthSync"
    /// Automatic refreshes (tab appear, sheet dismiss) reuse a recent sync.
    private static let watchSyncInterval: TimeInterval = 10 * 60
    /// Re-showing Home within this window doesn't re-read anything.
    private static let refreshInterval: TimeInterval = 60
    private var lastRefreshAt: Date?

    // MARK: - Refresh

    /// `force` = the user pulled to refresh or just logged something.
    /// Returns false when skipped (already running, or refreshed < 60s ago).
    @discardableResult
    func refresh(context: ModelContext, force: Bool = false) async -> Bool {
        guard !isRefreshing else { return false }
        if !force, let last = lastRefreshAt, Date().timeIntervalSince(last) < Self.refreshInterval { return false }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
        }

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let settings = UserSettings.load()
        refreshHeader(now: now)

        // 1. Pull the watch's overnight data (Pixel Watch → Google Health)
        //    into SwiftData first so the sleep / HRV / vitals reads see it.
        let watch = watchConnected ? GoogleHealthSyncService(modelContext: context) : nil
        let lastSync = UserDefaults.standard.object(forKey: Self.lastWatchSyncKey) as? Date
        let syncDue = force || lastSync.map { now.timeIntervalSince($0) > Self.watchSyncInterval } ?? true
        if let watch, syncDue {
            let firstSync = !UserDefaults.standard.bool(forKey: Self.backfillKey)
            await watch.sync(days: firstSync ? 14 : 2)
            DataDiagnostics.shared.watchError = watch.lastError
            if watch.lastError == nil {
                UserDefaults.standard.set(true, forKey: Self.backfillKey)
                UserDefaults.standard.set(now, forKey: Self.lastWatchSyncKey)
                lastWatchSync = now
            }
        } else {
            lastWatchSync = watchConnected ? lastSync : nil
            if !watchConnected { DataDiagnostics.shared.watchError = nil }
        }

        // 2. Challenge window drives how far back we read weights.
        let challenge = WeightChallenge.load()
        self.challenge = challenge
        let weightWindowStart = min(
            calendar.date(byAdding: .day, value: -45, to: today) ?? today,
            calendar.date(byAdding: .day, value: -3, to: challenge?.startDate ?? today) ?? today
        )

        // 3. Apple Health, in parallel. try? = a missing permission is not an error.
        async let hkWater = try? health.fetchDailySums(.dietaryWater, unit: .fluidOunceUS(), days: 7)
        async let hkWaterSources = health.sourceNames(.dietaryWater, since: today)
        async let hkSteps = try? health.fetchDailySums(.stepCount, unit: .count(), days: 7)
        async let hkProtein = try? health.fetchDailySums(.dietaryProtein, unit: .gram(), days: 1)
        async let hkEnergy = try? health.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: 8)
        async let hkActive = try? health.fetchDailySums(.activeEnergyBurned, unit: .kilocalorie(), days: 8)
        async let hkHRV = try? health.fetchSamples(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            from: calendar.date(byAdding: .day, value: -14, to: today) ?? today
        )
        async let hkHeart = try? health.fetchLatest(.heartRate, unit: .count().unitDivided(by: .minute()), withinDays: 1)
        async let hkResting = try? health.fetchLatest(.restingHeartRate, unit: .count().unitDivided(by: .minute()), withinDays: 3)
        async let hkBreathing = try? health.fetchLatest(.respiratoryRate, unit: .count().unitDivided(by: .minute()), withinDays: 3)
        async let hkSpO2 = try? health.fetchLatest(.oxygenSaturation, unit: .percent(), withinDays: 3)

        // 4. Watch live reads (heart rate now, steps, water logged to Google).
        let live = await watch?.fetchLive()
        let watchWaterOz = live?.waterOzToday
        let watchSteps = live?.stepsByDay ?? [:]
        let watchLiveHR = live?.heartRate

        // Resolve the Apple Health reads up front — `await` can't sit inside
        // the autoclosure on the right of `??`.
        let merged = await WeightDataSource.readings(context: context, since: weightWindowStart)
        let hkWaterByDay = await hkWater ?? [:]
        let hkStepsByDay = await hkSteps ?? [:]
        let hkProteinToday = (await hkProtein ?? [:])[today] ?? 0
        let hkEnergyByDay = await hkEnergy ?? [:]
        let hkEnergyToday = hkEnergyByDay[today] ?? 0
        let hkActiveByDay = await hkActive ?? [:]
        let hkHRVSamples = await hkHRV ?? []
        let hkHeartLatest = await hkHeart
        let hkRestingLatest = await hkResting
        let hkBreathingLatest = await hkBreathing
        let hkSpO2Latest = await hkSpO2
        let waterAppNames = await hkWaterSources

        // 5. Local data.
        let dayLogs = fetchDayLogs(context: context, since: calendar.date(byAdding: .day, value: -6, to: today) ?? today)
        let todayLog = dayLogs.first { calendar.isDate($0.date, inSameDayAs: today) }
        let todayEvents = fetchTodayEvents(context: context, now: now)
        let snapshots = fetchSnapshots(context: context, since: calendar.date(byAdding: .day, value: -14, to: today) ?? today)
        let sleeps = fetchSleeps(context: context, since: calendar.date(byAdding: .day, value: -7, to: today) ?? today)

        // ---- Weight
        weightReadings = merged
        latestWeight = merged.last
        if let challenge {
            progress = WeightChallengeEngine.progress(challenge: challenge, readings: merged, now: now)
            if force || race == nil || now.timeIntervalSince(raceCheckedAt ?? .distantPast) > 600 {
                raceCheckedAt = now
                race = await RacePace.report(challenge: challenge, readings: merged, context: context, now: now)
            }
        } else {
            progress = nil
            race = nil
        }

        // ---- Water: devices report running totals, quick-captures add on top.
        let deviceWater = max(hkWaterByDay[today] ?? 0, watchWaterOz ?? 0, todayLog?.waterOz ?? 0)
        let capturedWater = todayEvents
            .filter { $0.kindRaw == ContextEvent.Kind.water.rawValue }
            .reduce(0) { $0 + ($1.value ?? 0) }
        waterOz = deviceWater + capturedWater
        waterTargetOz = settings.waterTargetOz
        waterWeek = lastDays(7, today: today).map { day in
            if day == today { return waterOz }
            let log = dayLogs.first { calendar.isDate($0.date, inSameDayAs: day) }
            return max(hkWaterByDay[day] ?? 0, log?.waterOz ?? 0)
        }
        lastWaterReading = (hkWaterByDay[today] ?? 0) > 0 || (watchWaterOz ?? 0) > 0 ? now : nil

        // ---- Steps
        stepsSeries = lastDays(7, today: today).map { day in
            let log = dayLogs.first { calendar.isDate($0.date, inSameDayAs: day) }
            return Int(max(hkStepsByDay[day] ?? 0, watchSteps[day] ?? 0, Double(log?.steps ?? 0)))
        }
        steps = stepsSeries.last ?? 0

        // ---- Mile a day (walked or run): distance, on-foot workouts, or
        // steps — worked out per day and shared with the widgets.
        let mileHistory = await MileHistoryService.update(context: context, extraSteps: watchSteps, now: now)
        let mileSettings = MileSettings.load()
        stepsPerMileInUse = mileSettings.stepsPerMile
        mileGoal = mileSettings.goalMiles
        let mileWeek = mileHistory.last(7, today: now, calendar: calendar)
        milesToday = mileWeek.last?.miles ?? 0
        milesWeek = mileWeek.map(\.miles)
        ranToday = mileWeek.last?.ran ?? false
        mileStreak = mileHistory.currentStreak(today: now, goal: mileGoal, calendar: calendar)

        // ---- Fuel
        let mealEvents = todayEvents.filter { $0.kindRaw == ContextEvent.Kind.meal.rawValue }
        let loggedProtein = (todayLog?.proteinGrams ?? 0) + mealEvents.reduce(0) { $0 + ($1.secondaryValue ?? 0) }
        let loggedCalories = (todayLog?.caloriesConsumed ?? 0) + mealEvents.reduce(0) { $0 + ($1.value ?? 0) }
        proteinGrams = max(loggedProtein, hkProteinToday)
        caloriesIn = max(loggedCalories, hkEnergyToday)
        proteinTarget = settings.proteinTargetGrams
        let usualTarget = CalorieTarget.base(settings: settings, weight: latestWeight?.pounds ?? settings.currentWeight)
        calorieTarget = usualTarget
        finalPushUsualTarget = nil
        // Final push: the last 14 days run on the pace you need to win.
        if let c = challenge, FinalPush.isActive(end: c.endDate, now: now) {
            let strict = FinalPush.stricterTarget(normal: usualTarget, pace: race?.targetCalories)
            FinalPushStore.setTarget(strict < usualTarget ? strict : nil, now: now)
            if strict < usualTarget {
                calorieTarget = strict
                finalPushUsualTarget = usualTarget
            }
        } else {
            FinalPushStore.setTarget(nil)
        }
        if finalPushScheduledFor != .some(challenge?.endDate) {
            finalPushScheduledFor = .some(challenge?.endDate)
            let c = challenge
            Task { await FinalPushNotifications.reschedule(challenge: c) }
        }
        earned = await EarnedCalories.day(now, context: context)
        currentWeightForPaths = latestWeight?.pounds ?? settings.currentWeight

        // ---- Past week of days for "if every day were like…"
        let pastMeals = fetchMealEvents(context: context, since: calendar.date(byAdding: .day, value: -7, to: today) ?? today)
        pathDays = (1...7).compactMap { back -> PathProjection.DayRecord? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let log = dayLogs.first { calendar.isDate($0.date, inSameDayAs: day) }
            let meals = pastMeals
                .filter { calendar.isDate($0.logicalDate, inSameDayAs: day) }
                .reduce(0) { $0 + ($1.value ?? 0) }
            let eaten = max((log?.caloriesConsumed ?? 0) + meals, hkEnergyByDay[day] ?? 0)
            let stepCount = Int(max(hkStepsByDay[day] ?? 0, watchSteps[day] ?? 0, Double(log?.steps ?? 0)))
            return PathProjection.DayRecord(date: day, caloriesIn: eaten, activeKcal: hkActiveByDay[day], steps: stepCount)
        }

        // ---- HRV: prefer the watch's nightly RMSSD; fall back to Apple Health SDNN.
        //      Never mix the two in one series — they're different measures.
        let watchHRV = dailyValues(snapshots, calendar: calendar) { $0.hrv }
        if !watchHRV.isEmpty {
            hrvSeries = watchHRV
        } else {
            let byDay = Dictionary(grouping: hkHRVSamples) { calendar.startOfDay(for: $0.date) }
            hrvSeries = byDay.keys.sorted().map { day in
                let values = byDay[day]!.map(\.value)
                return values.reduce(0, +) / Double(values.count)
            }
        }
        hrv = hrvSeries.last
        let baselineValues = hrvSeries.dropLast()
        hrvBaseline = baselineValues.isEmpty ? nil : baselineValues.reduce(0, +) / Double(baselineValues.count)

        // ---- Sleep: main session per night; DayLog as fallback.
        var sleepByDay: [Date: Double] = [:]
        for s in sleeps {
            sleepByDay[s.logicalDate] = max(sleepByDay[s.logicalDate] ?? 0, Double(s.asleepMinutes) / 60)
        }
        for log in dayLogs where sleepByDay[log.date] == nil {
            if let minutes = log.sleepDurationMinutes, minutes > 0 {
                sleepByDay[log.date] = Double(minutes) / 60
            }
        }
        sleepSeries = sleepByDay.keys.sorted().suffix(7).map { sleepByDay[$0]! }
        sleepHours = sleepByDay[today] ?? sleepSeries.last

        // ---- Vitals: newest non-empty value per field — today's watch row
        //      can exist before every metric has been computed.
        restingHR = latestValue(snapshots) { $0.restingHeartRate } ?? hkRestingLatest?.value ?? todayLog?.sleepRestingHR
        if let live = watchLiveHR, now.timeIntervalSince(live.date) < 30 * 60 {
            heartRate = live.bpm
            heartRateIsLive = true
        } else if let live = hkHeartLatest, now.timeIntervalSince(live.date) < 2 * 3600 {
            heartRate = live.value
            heartRateIsLive = true
        } else {
            heartRate = restingHR
            heartRateIsLive = false
        }
        breathingRate = latestValue(snapshots) { $0.breathingRate }
            ?? sleeps.last?.avgBreathingRate
            ?? hkBreathingLatest?.value
        spO2 = latestValue(snapshots) { $0.spO2 }
            ?? sleeps.last?.avgSpO2
            ?? hkSpO2Latest.map { $0.value * 100 }

        // ---- Timeline & coach
        timeline = buildTimeline(context: context, now: now, todayLog: todayLog)
        insights = CoachEngine.insights(CoachEngine.Inputs(
            now: now,
            progress: progress,
            friendName: challenge?.friendDisplayName ?? "Your friend",
            scoring: challenge?.scoring ?? .percent,
            waterOz: waterOz,
            waterTargetOz: waterTargetOz,
            steps: steps,
            stepGoal: stepGoal,
            proteinGrams: proteinGrams,
            proteinTarget: proteinTarget,
            lastSleepHours: sleepHours,
            hrvToday: hrv,
            hrvBaseline: hrvBaseline
        ))

        snapshot = buildSnapshot(now: now, challenge: challenge)
        moodReading = AvatarMood.read(snapshot)
        refreshGoal(now: now)

        // ---- Data check (Devices screen): what each tile found, and where.
        let hkWaterToday = hkWaterByDay[today] ?? 0
        let hkStepsToday = hkStepsByDay[today] ?? 0
        let watchStepsToday = watchSteps[today] ?? 0
        let usedWatchVitals = latestValue(snapshots) { $0.spO2 ?? $0.breathingRate ?? $0.restingHeartRate } != nil
        var waterSources: [String] = []
        if hkWaterToday > 0 { waterSources.append(waterAppNames.isEmpty ? "Apple Health" : waterAppNames.joined(separator: ", ") + " via Apple Health") }
        if (watchWaterOz ?? 0) > 0 { waterSources.append("Google Health") }
        if capturedWater > 0 { waterSources.append("Logged in Dialed") }
        let waterSource: String? = waterSources.isEmpty ? nil : waterSources.joined(separator: " + ")
        let rows: [DataSourceStatus] = [
            DataSourceStatus(metric: "Weight",
                  value: latestWeight.map { String(format: "%.1f lb", $0.pounds) },
                  source: latestWeight?.source.displayName,
                  date: latestWeight?.date),
            DataSourceStatus(metric: "Water",
                  value: waterOz > 0 ? "\(Int(waterOz)) oz" : nil,
                  source: waterSource,
                  date: waterOz > 0 ? now : nil),
            DataSourceStatus(metric: "Steps",
                  value: steps > 0 ? steps.formatted() : nil,
                  source: watchStepsToday >= hkStepsToday && watchStepsToday > 0 ? "Pixel Watch" : (hkStepsToday > 0 ? "Apple Health" : nil),
                  date: steps > 0 ? now : nil),
            DataSourceStatus(metric: "Live heart rate",
                  value: heartRateIsLive ? heartRate.map { "\(Int($0)) bpm" } : nil,
                  source: watchLiveHR != nil && heartRateIsLive ? "Pixel Watch" : (heartRateIsLive ? "Apple Health" : nil),
                  date: watchLiveHR?.date ?? hkHeartLatest?.date),
            DataSourceStatus(metric: "Resting heart rate",
                  value: restingHR.map { "\(Int($0)) bpm" },
                  source: usedWatchVitals ? "Pixel Watch" : (restingHR != nil ? "Apple Health" : nil),
                  date: snapshots.last?.timestamp ?? hkRestingLatest?.date),
            DataSourceStatus(metric: "Sleep",
                  value: sleepHours.map { String(format: "%.1f h", $0) },
                  source: sleeps.isEmpty ? (sleepHours != nil ? "Apple Health" : nil) : "Pixel Watch",
                  date: sleeps.last?.endTime),
            DataSourceStatus(metric: "HRV",
                  value: hrv.map { "\(Int($0)) ms" },
                  source: watchHRV.isEmpty ? (hrv != nil ? "Apple Health (SDNN)" : nil) : "Pixel Watch (RMSSD)",
                  date: nil),
            DataSourceStatus(metric: "Blood oxygen",
                  value: spO2.map { "\(Int($0))%" },
                  source: spO2 == nil ? nil : (usedWatchVitals ? "Pixel Watch" : "Apple Health"),
                  date: nil),
            DataSourceStatus(metric: "Food",
                  value: caloriesIn > 0 ? "\(Int(caloriesIn)) calories · \(Int(proteinGrams)) g protein" : nil,
                  source: hkEnergyToday >= loggedCalories && hkEnergyToday > 0 ? "Apple Health" : (loggedCalories > 0 ? "Logged in Dialed" : nil),
                  date: nil)
        ]
        DataDiagnostics.shared.update(rows: rows)
        return true
    }

    /// Re-read the goal day (cheap; also called when it's edited).
    func refreshGoal(now: Date = Date()) {
        goalEvent = GoalEvent.load()
        if let event = goalEvent, event.date > now {
            goalProjection = WeightChallengeEngine.projection(readings: weightReadings, to: event.date, now: now)
        } else {
            goalProjection = nil
        }
        let target = goalEvent.map(\.date).flatMap { $0 > now ? $0 : nil }
            ?? Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        pathTargetDate = target
        pathScenarios = currentWeightForPaths > 0
            ? PathProjection.scenarios(days: pathDays, weight: currentWeightForPaths,
                                       calorieTarget: calorieTarget, goalDate: target, now: now)
            : []
    }

    private func buildSnapshot(now: Date, challenge: WeightChallenge?) -> HealthSnapshot {
        var s = HealthSnapshot()
        s.now = now
        s.firstName = firstName
        if let challenge, let p = progress {
            s.friendName = challenge.friendDisplayName
            s.challengeDay = p.dayNumber
            s.challengeDays = p.totalDays
            s.daysLeft = p.daysLeft
            s.scoring = challenge.scoring
            if p.startWeight != nil && p.currentWeight != nil {
                s.lostLbs = p.lostLbs
                s.lostPercent = p.lostPercent
                s.paceDelta = p.paceDelta
            }
            s.friendLostLbs = p.friend?.lostLbs
            s.friendLostPercent = p.friend?.lostPercent
            s.leader = p.leader
            s.margin = p.margin
            s.goalLossLbs = p.goalLossLbs
            s.projectedLossAtEnd = p.projectedLossAtEnd
            s.requiredDailyDeficit = p.requiredDailyDeficit
            s.weighedInToday = p.weighedInToday
        } else if let latest = latestWeight {
            s.weighedInToday = Calendar.current.isDateInToday(latest.date)
        }
        s.weight = latestWeight?.pounds
        s.sleepHours = sleepHours
        s.hrv = hrv
        s.hrvBaseline = hrvBaseline
        s.restingHR = restingHR
        s.waterOz = waterOz
        s.waterTargetOz = waterTargetOz
        s.steps = steps
        s.stepGoal = stepGoal
        s.miles = milesToday
        s.proteinGrams = proteinGrams
        s.proteinTarget = proteinTarget
        s.caloriesIn = caloriesIn
        s.calorieTarget = calorieBudget
        s.nextUp = timeline
            .filter { $0.status == .upcoming || $0.status == .active }
            .prefix(3)
            .map { "\($0.start.formatted(date: .omitted, time: .shortened)) \($0.title)" }
        return s
    }

    /// Newest non-nil value of a field across the watch's daily rows.
    private func latestValue(_ snapshots: [BiometricSnapshot], _ value: (BiometricSnapshot) -> Double?) -> Double? {
        for s in snapshots.reversed() {
            if let v = value(s) { return v }
        }
        return nil
    }

    /// Rough cutting target: ~15 kcal/lb maintenance minus 500.
    static func estimatedCutCalories(weight: Double) -> Double {
        ((weight * 15 - 500) / 50).rounded() * 50
    }

    // MARK: - Header

    private func refreshHeader(now: Date) {
        firstName = UserDefaults.standard.string(forKey: "user.firstName") ?? ""
        let df = DateFormatter()
        df.dateFormat = "EEE, MMM d"
        dateLine = df.string(from: now)
    }

    // MARK: - Fetchers

    private func fetchDayLogs(context: ModelContext, since start: Date) -> [DayLog] {
        let desc = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date >= start },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    private func fetchTodayEvents(context: ModelContext, now: Date) -> [ContextEvent] {
        let day = Calendar.current.logicalStartOfDay(for: now)
        let desc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate == day }
        )
        return (try? context.fetch(desc)) ?? []
    }

    private func fetchMealEvents(context: ModelContext, since start: Date) -> [ContextEvent] {
        let meal = ContextEvent.Kind.meal.rawValue
        let desc = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate >= start && $0.kindRaw == meal }
        )
        return (try? context.fetch(desc)) ?? []
    }

    private func fetchSnapshots(context: ModelContext, since start: Date) -> [BiometricSnapshot] {
        let desc = FetchDescriptor<BiometricSnapshot>(
            predicate: #Predicate { $0.timestamp >= start },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    private func fetchSleeps(context: ModelContext, since start: Date) -> [SleepSession] {
        let desc = FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.endTime >= start },
            sortBy: [SortDescriptor(\.endTime)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    // MARK: - Series helpers

    private func lastDays(_ count: Int, today: Date) -> [Date] {
        (0..<count).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: today)
        }
    }

    /// One value per day (the latest non-nil reading that day), oldest first.
    private func dailyValues(
        _ snapshots: [BiometricSnapshot],
        calendar: Calendar,
        _ value: (BiometricSnapshot) -> Double?
    ) -> [Double] {
        var byDay: [Date: Double] = [:]
        for s in snapshots {
            if let v = value(s) { byDay[calendar.startOfDay(for: s.timestamp)] = v }
        }
        return byDay.keys.sorted().map { byDay[$0]! }
    }

    // MARK: - Timeline

    private func buildTimeline(context: ModelContext, now: Date, todayLog: DayLog?) -> [HomeTimelineItem] {
        let dayStart = Calendar.current.logicalStartOfDay(for: now)
        let planDesc = FetchDescriptor<DailyPlan>(predicate: #Predicate { $0.date == dayStart })

        if let plan = (try? context.fetch(planDesc))?.first,
           let blocks = plan.blocks, !blocks.isEmpty {
            return blocks
                .filter { $0.status != .skipped }
                .sorted { $0.startTime < $1.startTime }
                .map { block in
                    let status: HomeTimelineItem.Status
                    switch block.liveStatus(now: now) {
                    case .done:            status = .done
                    case .active:          status = .active
                    case .due:             status = .missed
                    case .upcoming:
                        // liveStatus keeps finished, unchecked duration blocks
                        // at .upcoming — past their end they were missed.
                        status = block.endTime < now ? .missed : .upcoming
                    case .skipped:         status = .missed
                    }
                    let duration = max(block.durationMinutes, 20)
                    return HomeTimelineItem(
                        id: block.id,
                        title: block.title,
                        start: block.startTime,
                        end: block.startTime.addingTimeInterval(TimeInterval(duration * 60)),
                        status: status,
                        tint: Self.tint(for: block.kind)
                    )
                }
        }

        // Legacy checklist fallback.
        guard let log = todayLog else { return [] }
        let base = Calendar.current.startOfDay(for: now)
        return (log.checklistItems ?? []).compactMap { item -> HomeTimelineItem? in
            guard let start = Calendar.current.date(
                bySettingHour: item.scheduledHour, minute: item.scheduledMinute, second: 0, of: base
            ) else { return nil }
            let done = item.checklistStatus == .done
            return HomeTimelineItem(
                id: item.id,
                title: item.displayTitle,
                start: start,
                end: start.addingTimeInterval(30 * 60),
                status: done ? .done : (start <= now ? .missed : .upcoming),
                tint: Neka.green
            )
        }
        .sorted { $0.start < $1.start }
    }

    static func tint(for kind: TemplateBlock.Kind) -> Color {
        switch kind {
        case .workout, .cardio:                return Neka.blue
        case .meal, .caffeine:                 return Neka.orange
        case .hydration:                       return Neka.sky
        case .sleep, .windDown, .rest:         return Neka.lavender
        case .wake, .skincare, .supplement:    return Neka.green
        case .deepWork, .mood, .routine:       return Neka.amber
        }
    }
}
