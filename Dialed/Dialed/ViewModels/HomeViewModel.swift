//
//  HomeViewModel.swift
//  Dialed
//
//  Drives the Neka-style Home tab. Pulls from every source you own and
//  merges them into one picture:
//
//    • Pixel Watch → Fitbit Web API (sleep, HRV, resting HR, SpO2,
//      breathing, steps) via FitbitSyncService + direct reads
//    • Smart scale → Apple Health body mass and/or Fitbit weight log,
//      plus manual weigh-ins (WeightEntry)
//    • Smart water bottle → Apple Health dietary water and/or Fitbit water
//      log, plus quick-captured water (ContextEvent)
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
    let stepGoal = 10_000

    @Published var proteinGrams: Double = 0
    @Published var proteinTarget: Double = 190
    @Published var caloriesIn: Double = 0
    @Published var calorieTarget: Double = 2_200

    // MARK: - Timeline & coach

    @Published var timeline: [HomeTimelineItem] = []
    @Published var insights: [CoachInsight] = []

    // MARK: - Device freshness

    @Published var lastWatchSync: Date?
    @Published var lastWaterReading: Date?
    @Published var isRefreshing = false

    /// Today in one value — fed to Apple Intelligence and the fallbacks.
    @Published var snapshot = HealthSnapshot()

    private let health = HealthKitManager.shared
    private var fitbitConnected: Bool { FitbitTokenStore.isConnected }
    private static let backfillKey = "home.fitbitBackfilled.v1"
    private static let lastFitbitSyncKey = "home.lastFitbitSync"
    /// Fitbit allows 150 calls/hour; a full day sync is ~6. Automatic
    /// refreshes (tab appear, sheet dismiss) reuse a recent sync.
    private static let fitbitSyncInterval: TimeInterval = 10 * 60

    // MARK: - Refresh

    /// `force` = the user pulled to refresh, so always re-sync the watch.
    func refresh(context: ModelContext, force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let settings = UserSettings.load()
        refreshHeader(now: now)

        // 1. Pull the watch's overnight data into SwiftData first so the
        //    sleep / HRV / vitals reads below see it.
        var fitbitSyncError: String?
        let lastSync = UserDefaults.standard.object(forKey: Self.lastFitbitSyncKey) as? Date
        let syncDue = force || lastSync.map { now.timeIntervalSince($0) > Self.fitbitSyncInterval } ?? true
        if fitbitConnected && syncDue {
            let sync = FitbitSyncService(modelContext: context)
            if !UserDefaults.standard.bool(forKey: Self.backfillKey) {
                await sync.backfill(days: 14)
                UserDefaults.standard.set(true, forKey: Self.backfillKey)
            } else {
                await sync.syncDay(today)
                if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                    await sync.syncDay(yesterday)
                }
            }
            try? context.save()
            fitbitSyncError = sync.lastError
            if sync.lastError == nil {
                lastWatchSync = sync.lastSyncedAt
                UserDefaults.standard.set(now, forKey: Self.lastFitbitSyncKey)
            }
        } else if fitbitConnected {
            lastWatchSync = lastSync
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
        async let hkSteps = try? health.fetchDailySums(.stepCount, unit: .count(), days: 7)
        async let hkProtein = try? health.fetchDailySums(.dietaryProtein, unit: .gram(), days: 1)
        async let hkEnergy = try? health.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: 1)
        async let hkHRV = try? health.fetchSamples(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            from: calendar.date(byAdding: .day, value: -14, to: today) ?? today
        )
        async let hkHeart = try? health.fetchLatest(.heartRate, unit: .count().unitDivided(by: .minute()), withinDays: 1)
        async let hkResting = try? health.fetchLatest(.restingHeartRate, unit: .count().unitDivided(by: .minute()), withinDays: 3)
        async let hkBreathing = try? health.fetchLatest(.respiratoryRate, unit: .count().unitDivided(by: .minute()), withinDays: 3)
        async let hkSpO2 = try? health.fetchLatest(.oxygenSaturation, unit: .percent(), withinDays: 3)

        if fitbitConnected, let error = fitbitSyncError {
            DataDiagnostics.shared.fitbitError = error
        } else {
            DataDiagnostics.shared.fitbitError = nil
        }

        // 4. Fitbit direct reads (live heart rate, bottle, steps).
        var fitbitWaterOz: Double?
        var fitbitSteps: [Date: Double] = [:]
        var fitbitLiveHR: (date: Date, bpm: Double)?
        if fitbitConnected {
            let api = FitbitAPIClient.shared
            if let resp = try? await api.heartIntraday(on: today),
               let last = resp.intraday?.dataset.last,
               let date = FitbitAPIClient.parseDay(FitbitAPIClient.iso(today), time: last.time) {
                fitbitLiveHR = (date, last.value)
            }
            if let resp = try? await api.water(on: today), let ml = resp.summary?.water {
                fitbitWaterOz = ml / 29.5735
            }
            if let resp = try? await api.stepsSeries(endingOn: today) {
                for point in resp.activitiesSteps {
                    if let day = FitbitAPIClient.parseDay(point.dateTime), let value = Double(point.value) {
                        fitbitSteps[calendar.startOfDay(for: day)] = value
                    }
                }
            }
        }

        // Resolve the Apple Health reads up front — `await` can't sit inside
        // the autoclosure on the right of `??`.
        let merged = await WeightDataSource.readings(context: context, since: weightWindowStart)
        let hkWaterByDay = await hkWater ?? [:]
        let hkStepsByDay = await hkSteps ?? [:]
        let hkProteinToday = (await hkProtein ?? [:])[today] ?? 0
        let hkEnergyToday = (await hkEnergy ?? [:])[today] ?? 0
        let hkHRVSamples = await hkHRV ?? []
        let hkHeartLatest = await hkHeart
        let hkRestingLatest = await hkResting
        let hkBreathingLatest = await hkBreathing
        let hkSpO2Latest = await hkSpO2

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
        } else {
            progress = nil
        }

        // ---- Water: devices report running totals, quick-captures add on top.
        let deviceWater = max(hkWaterByDay[today] ?? 0, fitbitWaterOz ?? 0, todayLog?.waterOz ?? 0)
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
        lastWaterReading = (hkWaterByDay[today] ?? 0) > 0 || (fitbitWaterOz ?? 0) > 0 ? now : nil

        // ---- Steps
        stepsSeries = lastDays(7, today: today).map { day in
            let log = dayLogs.first { calendar.isDate($0.date, inSameDayAs: day) }
            return Int(max(hkStepsByDay[day] ?? 0, fitbitSteps[day] ?? 0, Double(log?.steps ?? 0)))
        }
        steps = stepsSeries.last ?? 0

        // ---- Fuel
        let mealEvents = todayEvents.filter { $0.kindRaw == ContextEvent.Kind.meal.rawValue }
        let loggedProtein = (todayLog?.proteinGrams ?? 0) + mealEvents.reduce(0) { $0 + ($1.secondaryValue ?? 0) }
        let loggedCalories = (todayLog?.caloriesConsumed ?? 0) + mealEvents.reduce(0) { $0 + ($1.value ?? 0) }
        proteinGrams = max(loggedProtein, hkProteinToday)
        caloriesIn = max(loggedCalories, hkEnergyToday)
        proteinTarget = settings.proteinTargetGrams
        calorieTarget = settings.calorieTarget ?? Self.estimatedCutCalories(weight: latestWeight?.pounds ?? settings.currentWeight)

        // ---- HRV: prefer the watch's nightly RMSSD; fall back to Apple Health SDNN.
        //      Never mix the two in one series — they're different measures.
        let fitbitHRV = dailyValues(snapshots, calendar: calendar) { $0.hrv }
        if !fitbitHRV.isEmpty {
            hrvSeries = fitbitHRV
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
        if let live = fitbitLiveHR, now.timeIntervalSince(live.date) < 30 * 60 {
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

        // ---- Data check (Devices screen): what each tile found, and where.
        let hkWaterToday = hkWaterByDay[today] ?? 0
        let hkStepsToday = hkStepsByDay[today] ?? 0
        let fitbitStepsToday = fitbitSteps[today] ?? 0
        let usedFitbitVitals = latestValue(snapshots) { $0.spO2 ?? $0.breathingRate ?? $0.restingHeartRate } != nil
        var waterSources: [String] = []
        if hkWaterToday > 0 { waterSources.append("Apple Health") }
        if (fitbitWaterOz ?? 0) > 0 { waterSources.append("Fitbit") }
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
                  source: fitbitStepsToday >= hkStepsToday && fitbitStepsToday > 0 ? "Pixel Watch (Fitbit)" : (hkStepsToday > 0 ? "Apple Health" : nil),
                  date: steps > 0 ? now : nil),
            DataSourceStatus(metric: "Live heart rate",
                  value: heartRateIsLive ? heartRate.map { "\(Int($0)) bpm" } : nil,
                  source: fitbitLiveHR != nil && heartRateIsLive ? "Pixel Watch (Fitbit)" : (heartRateIsLive ? "Apple Health" : nil),
                  date: fitbitLiveHR?.date ?? hkHeartLatest?.date),
            DataSourceStatus(metric: "Resting heart rate",
                  value: restingHR.map { "\(Int($0)) bpm" },
                  source: usedFitbitVitals ? "Pixel Watch (Fitbit)" : (restingHR != nil ? "Apple Health" : nil),
                  date: snapshots.last?.timestamp ?? hkRestingLatest?.date),
            DataSourceStatus(metric: "Sleep",
                  value: sleepHours.map { String(format: "%.1f h", $0) },
                  source: sleeps.isEmpty ? (sleepHours != nil ? "Apple Health" : nil) : "Pixel Watch (Fitbit)",
                  date: sleeps.last?.endTime),
            DataSourceStatus(metric: "HRV",
                  value: hrv.map { "\(Int($0)) ms" },
                  source: fitbitHRV.isEmpty ? (hrv != nil ? "Apple Health (SDNN)" : nil) : "Pixel Watch (RMSSD)",
                  date: nil),
            DataSourceStatus(metric: "Blood oxygen",
                  value: spO2.map { "\(Int($0))%" },
                  source: spO2 == nil ? nil : (usedFitbitVitals ? "Pixel Watch (Fitbit)" : "Apple Health"),
                  date: nil),
            DataSourceStatus(metric: "Food",
                  value: caloriesIn > 0 ? "\(Int(caloriesIn)) kcal · \(Int(proteinGrams)) g protein" : nil,
                  source: hkEnergyToday >= loggedCalories && hkEnergyToday > 0 ? "Apple Health" : (loggedCalories > 0 ? "Logged in Dialed" : nil),
                  date: nil)
        ]
        DataDiagnostics.shared.update(rows: rows)
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
        s.proteinGrams = proteinGrams
        s.proteinTarget = proteinTarget
        s.caloriesIn = caloriesIn
        s.calorieTarget = calorieTarget
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
                    case .upcoming:        status = .upcoming
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
