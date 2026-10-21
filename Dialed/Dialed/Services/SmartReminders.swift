//
//  SmartReminders.swift
//  Dialed
//
//  Schedules the nudges ReminderPlanner picks. Every refresh removes the
//  smart reminders still pending and schedules a fresh plan, so anything
//  you've caught up on quietly disappears. Refreshes run when the app
//  becomes active, after anything is logged (.dialedDataDidChange), and in
//  a background app refresh task that re-reads Apple Health + SwiftData —
//  so WaterH sips that land while the app is closed still cancel water
//  nudges.
//
//  Tapping a reminder routes through `deliverRoute` → MainTabView, which
//  opens the water sheet, food log, weigh-in or weekly review.
//

import Foundation
import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import HealthKit

@MainActor
enum SmartReminders {

    /// Must match BGTaskSchedulerPermittedIdentifiers in Dialed-Info.plist.
    nonisolated static let backgroundTaskID = "org.robertwiscount.Dialed.refresh"
    nonisolated static let openRouteNotification = Notification.Name("DialedOpenReminderRoute")
    nonisolated private static let pendingRouteKey = "smartReminders.pendingRoute"
    nonisolated private static let pendingRouteDateKey = "smartReminders.pendingRouteDate"

    private static var isRefreshing = false
    private static var backgroundContainer: ModelContainer?

    // MARK: - Permission

    /// Asks for notification permission (only called when you turn
    /// reminders on). Returns whether we're allowed to post.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await NotificationManager.shared.requestAuthorization()
        default:
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: - Refresh

    /// Re-plan today's nudges and the Sunday review from current data.
    static func refresh(context: ModelContext) async {
        let settings = ReminderSettings.load()
        guard settings.enabled else {
            await replacePending(with: [])
            scheduleBackgroundRefresh()   // cancels it while off
            return
        }
        guard await isAuthorized() else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        // Apple Health unreadable (phone locked in the background) → keep
        // whatever is already scheduled rather than plan from zeros.
        guard let inputs = await loadInputs(context: context, now: now) else { return }
        var reminders = ReminderPlanner.plan(inputs, settings: settings)
        if let morning = ReminderPlanner.tomorrowWeighIn(now: now, settings: settings) {
            reminders.append(morning)
        }
        if let review = ReminderPlanner.weeklyReview(now: now, settings: settings) {
            reminders.append(review)
        }
        // The big day (a wedding): no nudges at all.
        reminders.removeAll { EventModeStore.isEventDay($0.fireDate) }
        await replacePending(with: reminders)
        scheduleBackgroundRefresh()
    }

    /// Smart reminders currently waiting to fire, soonest first.
    static func pending() async -> [(date: Date, title: String)] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests
            .filter { $0.identifier.hasPrefix(ReminderPlanner.idPrefix) }
            .compactMap { r -> (date: Date, title: String)? in
                guard let trigger = r.trigger as? UNCalendarNotificationTrigger,
                      let date = trigger.nextTriggerDate() else { return nil }
                return (date, r.content.title)
            }
            .sorted { $0.date < $1.date }
    }

    private static func replacePending(with reminders: [ReminderPlanner.Reminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        if !old.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: old)
        }
        let calendar = Calendar.current
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.threadIdentifier = "dialed.smartReminders"
            content.userInfo = [ReminderRoute.userInfoKey: r.route.rawValue]
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
            } catch {
                print("SmartReminders: couldn't schedule \(r.id): \(error)")
            }
        }
    }

    // MARK: - Today's numbers

    /// Same merge as Home: Apple Health (WaterH, scale, food apps) plus
    /// what you've logged in Dialed. nil when Apple Health can't be read.
    private static func loadInputs(context: ModelContext, now: Date) async -> ReminderPlanner.Inputs? {
        let health = HealthKitManager.shared
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let logicalDay = calendar.logicalStartOfDay(for: now)
        let settings = UserSettings.load()

        let hkWater: Double
        let hkSteps: Double
        let hkProtein: Double
        let hkEnergy: Double
        do {
            hkWater = try await health.fetchDailySums(.dietaryWater, unit: .fluidOunceUS(), days: 1)[today] ?? 0
            hkSteps = try await health.fetchDailySums(.stepCount, unit: .count(), days: 1)[today] ?? 0
            hkProtein = try await health.fetchDailySums(.dietaryProtein, unit: .gram(), days: 1)[today] ?? 0
            hkEnergy = try await health.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: 1)[today] ?? 0
        } catch {
            return nil
        }
        let lastFoodSample = try? await health.fetchLatest(.dietaryEnergyConsumed, unit: .kilocalorie(), withinDays: 1)
        let weights = await WeightDataSource.readings(context: context, since: today)

        let logDesc = FetchDescriptor<DayLog>(predicate: #Predicate { $0.date >= today })
        let todayLog = ((try? context.fetch(logDesc)) ?? []).first { calendar.isDate($0.date, inSameDayAs: today) }
        let eventDesc = FetchDescriptor<ContextEvent>(predicate: #Predicate { $0.logicalDate == logicalDay })
        let events = (try? context.fetch(eventDesc)) ?? []
        let meals = events.filter { $0.kindRaw == ContextEvent.Kind.meal.rawValue }
        let capturedWater = events
            .filter { $0.kindRaw == ContextEvent.Kind.water.rawValue }
            .reduce(0) { $0 + ($1.value ?? 0) }

        let loggedProtein = (todayLog?.proteinGrams ?? 0) + meals.reduce(0) { $0 + ($1.secondaryValue ?? 0) }
        let loggedCalories = (todayLog?.caloriesConsumed ?? 0) + meals.reduce(0) { $0 + ($1.value ?? 0) }
        let latestWeight = weights.last?.pounds ?? settings.currentWeight

        var lastMeal = meals.map(\.timestamp).max()
        if let sample = lastFoodSample, calendar.isDate(sample.date, inSameDayAs: now) {
            lastMeal = max(lastMeal ?? sample.date, sample.date)
        }

        var inputs = ReminderPlanner.Inputs(now: now)
        inputs.waterOz = max(hkWater, todayLog?.waterOz ?? 0) + capturedWater
        inputs.waterTargetOz = settings.waterTargetOz
        inputs.proteinGrams = max(loggedProtein, hkProtein)
        inputs.proteinTarget = settings.proteinTargetGrams
        inputs.caloriesIn = max(loggedCalories, hkEnergy)
        inputs.calorieTarget = CalorieTarget.current(settings: settings, weight: latestWeight)
        inputs.steps = Int(max(hkSteps, Double(todayLog?.steps ?? 0)))
        inputs.stepGoal = 10_000
        inputs.weighedInToday = weights.contains { calendar.isDate($0.date, inSameDayAs: now) }
        inputs.lastMealAt = lastMeal
        inputs.proteinCurve = ProteinPacing.curve(context: context, now: now)
        inputs.deliveredToday = await deliveredToday(calendar: calendar, now: now)
        return inputs
    }

    private static func deliveredToday(calendar: Calendar, now: Date) async -> Int {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        return delivered.filter {
            $0.request.identifier.hasPrefix(ReminderPlanner.idPrefix)
                && !$0.request.identifier.contains(ReminderKind.weeklyReview.rawValue)
                && calendar.isDate($0.date, inSameDayAs: now)
        }.count
    }

    // MARK: - Background refresh

    /// Call from application(_:didFinishLaunchingWithOptions:).
    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Ask iOS to wake us again in ~45 minutes (it decides when).
    nonisolated static func scheduleBackgroundRefresh() {
        // Reminders or a live challenge (your friend's weigh-ins) need it.
        guard ReminderSettings.load().enabled || ChallengeSync.hasLiveChallenge else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 45 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("SmartReminders: couldn't schedule background refresh: \(error)")
        }
    }

    nonisolated private static func handle(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await refreshInBackground()
            if !Task.isCancelled { task.setTaskCompleted(success: true) }
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private static func refreshInBackground() async {
        if backgroundContainer == nil {
            backgroundContainer = try? DialedSchema.makeContainer()
        }
        guard let container = backgroundContainer else { return }
        let context = ModelContext(container)
        await HeadToHeadSync.run(context: context, force: true)
        await refresh(context: context)
    }

    // MARK: - Tap routing

    /// Called by AppDelegate when a reminder is tapped. Stores the route
    /// (in case the tab view isn't up yet) and tells it to look.
    nonisolated static func deliverRoute(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: pendingRouteKey)
        UserDefaults.standard.set(Date(), forKey: pendingRouteDateKey)
        NotificationCenter.default.post(name: openRouteNotification, object: nil)
    }

    /// Takes the pending route, if it's fresh (tapped < 10 min ago).
    static func takePendingRoute() -> ReminderRoute? {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: pendingRouteKey)
            defaults.removeObject(forKey: pendingRouteDateKey)
        }
        guard let raw = defaults.string(forKey: pendingRouteKey),
              let date = defaults.object(forKey: pendingRouteDateKey) as? Date,
              Date().timeIntervalSince(date) < 10 * 60 else { return nil }
        return ReminderRoute(rawValue: raw)
    }
}

// MARK: - Driver for the tab view

/// Refreshes reminders on launch, when the app becomes active and after
/// anything is logged; routes reminder taps.
struct SmartRemindersDriver: ViewModifier {
    @ObservedObject var router: AppRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                // Let the tabs mount before routing a cold-launch tap.
                try? await Task.sleep(nanoseconds: 900_000_000)
                openPendingRoute()
                await SmartReminders.refresh(context: modelContext)
                await HeadToHeadSync.run(context: modelContext, force: true)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task {
                        await SmartReminders.refresh(context: modelContext)
                        await HeadToHeadSync.run(context: modelContext)
                    }
                case .background:
                    SmartReminders.scheduleBackgroundRefresh()
                default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
                Task {
                    // Give Apple Health a moment to settle writes.
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await SmartReminders.refresh(context: modelContext)
                    // A new scale reading goes up to the live challenge.
                    await HeadToHeadSync.run(context: modelContext)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: SmartReminders.openRouteNotification)) { _ in
                openPendingRoute()
            }
    }

    private func openPendingRoute() {
        guard let route = SmartReminders.takePendingRoute() else { return }
        switch route {
        case .water:        router.quickLog = .water
        case .weighIn:      router.quickLog = .weighIn
        case .foodLog:      router.openHome(.foodLog)
        case .weeklyReview: router.openHome(.weeklyReview)
        case .home:         router.select(.home)
        case .challenge:    router.select(.challenge)
        case .weeklyReport: router.openChallenge(.report)
        case .progressPhoto:
            UserDefaults.standard.set(true, forKey: MonthlyPhotoReminder.openCameraKey)
            router.openHome(.progressPhotos)
        }
    }
}

extension View {
    func smartReminders(router: AppRouter) -> some View {
        modifier(SmartRemindersDriver(router: router))
    }
}
