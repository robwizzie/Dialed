//
//  WakeAlarmScheduler.swift
//  Dialed
//
//  Rings the wake-up alarm. On iOS 26 it uses AlarmKit, so it sounds like
//  the Clock app: through Silent mode and Focus, full screen on the Lock
//  Screen, with a "Start mission" button that opens Dialed. On older iOS
//  it falls back to a burst of notifications, which can't ring through
//  Silent mode (the settings screen says so).
//
//  Also owns the follow-ups that make it Alarmy-like: re-rings when you
//  stop without the mission, stall or leave mid-mission, and the
//  wake-up check a few minutes after you're done.
//

import Foundation
import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
import AppIntents
#endif

// MARK: - State

/// What the alarm system has scheduled and what's been beaten.
struct WakeAlarmState: Codable, Equatable {
    /// AlarmKit IDs of the scheduled wake-ups.
    var scheduledIDs: [String] = []
    /// The pending re-ring (stalled / left / stopped without the mission).
    var reRingID: String?
    var reRingAt: Date?
    /// The wake-up check: when it asks, and the alarm armed behind it.
    var wakeCheckAt: Date?
    var wakeCheckID: String?
    /// WakeAlarmPlan.key of every alarm whose mission is done.
    var completed: [String] = []
    var snoozedUntil: Date?
    var snoozesUsed: [String: Int] = [:]
    /// Set when "Start mission" is tapped on the alarm.
    var missionRequestedAt: Date?

    private static let key = "wakeAlarm.state"

    static func load(_ defaults: UserDefaults = .standard) -> WakeAlarmState {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(WakeAlarmState.self, from: data) else { return WakeAlarmState() }
        return s
    }

    func save(_ defaults: UserDefaults = .standard) {
        var copy = self
        copy.completed = Array(copy.completed.suffix(60))
        if let data = try? JSONEncoder().encode(copy) { defaults.set(data, forKey: Self.key) }
    }
}

#if canImport(AlarmKit)
/// Carried on each AlarmKit alarm.
@available(iOS 26.0, *)
struct DialedAlarmMetadata: AlarmMetadata {
    var mission: String
    init(mission: String = "") { self.mission = mission }
}
#endif

// MARK: - Scheduler

@MainActor
enum WakeAlarmScheduler {

    /// Real alarms (iOS 26 AlarmKit) vs. the notification fallback.
    static var ringsThroughSilent: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    private static let mainPrefix = "wakealarm_main_"
    private static let reRingPrefix = "wakealarm_rering_"
    private static let checkPrefix = "wakealarm_check_"

    static func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: return true
            case .denied:     return false
            case .notDetermined:
                return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
            @unknown default: return false
            }
        }
        #endif
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Rebuild the next week of wake-up alarms from the schedule.
    static func reschedule(now: Date = Date()) async {
        let settings = WakeAlarmSettings.load()
        var state = WakeAlarmState.load()
        cancel(ids: state.scheduledIDs)
        state.scheduledIDs = []
        removeNotifications(prefix: mainPrefix)
        defer { state.save() }
        guard settings.enabled else { return }

        let dates = WakeAlarmPlan.fireDates(schedule: WakeSchedule.load(), extra: settings.extra, from: now)
        let mission = settings.effectiveMission
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for date in dates {
                if let id = await scheduleAlarm(at: date, title: "Time to get up", mission: mission) {
                    state.scheduledIDs.append(id.uuidString)
                }
            }
            return
        }
        #endif
        // Fallback: six nudges a minute apart (notification limit is 64).
        for date in dates.prefix(8) {
            for minute in 0..<6 {
                await notify(id: "\(mainPrefix)\(WakeAlarmPlan.key(date))_\(minute)",
                             title: minute == 0 ? "⏰ Time to get up" : "⏰ Still ringing",
                             body: "Open Dialed and finish your \(mission.title.lowercased()) mission to stop it.",
                             at: date.addingTimeInterval(Double(minute) * 60))
            }
        }
    }

    /// Ring again at `date` (replaces any pending re-ring).
    static func ringAgain(at date: Date, title: String = "Still in bed? Finish your mission") async {
        var state = WakeAlarmState.load()
        cancel(ids: state.reRingID.map { [$0] } ?? [])
        removeNotifications(prefix: reRingPrefix)
        state.reRingID = await armOne(at: date, title: title, prefix: reRingPrefix)
        state.reRingAt = date
        state.save()
    }

    static func cancelReRing() {
        var state = WakeAlarmState.load()
        cancel(ids: state.reRingID.map { [$0] } ?? [])
        removeNotifications(prefix: reRingPrefix)
        state.reRingID = nil
        state.reRingAt = nil
        state.save()
    }

    /// Silence whatever is ringing right now (the mission has started).
    static func stopRinging() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for alarm in (try? AlarmManager.shared.alarms) ?? [] where alarm.state == .alerting {
                try? AlarmManager.shared.stop(id: alarm.id)
            }
        }
        #endif
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// A nudge after `wakeCheckDelay`, and the alarm again if it isn't answered.
    static func scheduleWakeCheck(now: Date = Date()) async {
        var state = WakeAlarmState.load()
        let ask = now.addingTimeInterval(WakeAlarmPlan.wakeCheckDelay)
        await notify(id: "\(checkPrefix)ask", title: "Still up? 👀",
                     body: "Open Dialed within 2 minutes or your alarm rings again.", at: ask)
        cancel(ids: state.wakeCheckID.map { [$0] } ?? [])
        state.wakeCheckID = await armOne(at: ask.addingTimeInterval(WakeAlarmPlan.wakeCheckWindow),
                                         title: "Wake-up check missed", prefix: checkPrefix)
        state.wakeCheckAt = ask
        state.save()
    }

    static func cancelWakeCheck() {
        var state = WakeAlarmState.load()
        cancel(ids: state.wakeCheckID.map { [$0] } ?? [])
        removeNotifications(prefix: checkPrefix)
        state.wakeCheckID = nil
        state.wakeCheckAt = nil
        state.save()
    }

    // MARK: - Pieces

    /// One alarm (AlarmKit) or a short burst of notifications (fallback).
    private static func armOne(at date: Date, title: String, prefix: String) async -> String? {
        let mission = WakeAlarmSettings.load().effectiveMission
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await scheduleAlarm(at: max(date, Date().addingTimeInterval(2)), title: title, mission: mission)?.uuidString
        }
        #endif
        for i in 0..<3 {
            await notify(id: "\(prefix)\(Int(date.timeIntervalSince1970))_\(i)", title: "⏰ \(title)",
                         body: "Open Dialed and finish your \(mission.title.lowercased()) mission.",
                         at: date.addingTimeInterval(Double(i) * 30))
        }
        return nil
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func scheduleAlarm(at date: Date, title: String, mission: WakeMission) async -> UUID? {
        let id = UUID()
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(text: "Start mission", textColor: .black, systemImageName: mission.symbol),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes<DialedAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: DialedAlarmMetadata(mission: mission.rawValue),
            tintColor: Neka.green)
        let configuration = AlarmManager.AlarmConfiguration<DialedAlarmMetadata>(
            countdownDuration: nil,
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: StopWakeAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: StartWakeMissionIntent(alarmID: id.uuidString),
            sound: .default)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return id
        } catch {
            print("⚠️ [WakeAlarm] schedule failed: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    private static func cancel(ids: [String]) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for raw in ids {
                if let id = UUID(uuidString: raw) { try? AlarmManager.shared.cancel(id: id) }
            }
        }
        #endif
    }

    private static func notify(id: String, title: String, body: String, at date: Date) async {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func removeNotifications(prefix: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }
}

// MARK: - Alarm buttons

#if canImport(AlarmKit)
/// "Start mission" on the alarm: opens Dialed straight into the mission.
@available(iOS 26.0, *)
struct StartWakeMissionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start wake-up mission"
    static let openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    @MainActor
    func perform() async throws -> some IntentResult {
        WakeAlarmCoordinator.shared.missionRequested()
        return .result()
    }
}

/// "Stop" can't be removed from a system alarm, so like Alarmy it doesn't
/// really stop it: without the mission done, the alarm comes back shortly.
@available(iOS 26.0, *)
struct StopWakeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop wake-up alarm"
    static let openAppWhenRun = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WakeAlarmCoordinator.shared.stoppedFromAlert()
        return .result()
    }
}
#endif

// MARK: - Coordinator

/// The mission flow: present it when an alarm is ringing or missed, keep
/// a re-ring armed while you're at it, and run the wake-up check after.
@MainActor
final class WakeAlarmCoordinator: ObservableObject {
    static let shared = WakeAlarmCoordinator()

    struct Run: Identifiable, Equatable {
        let id: String
        let mission: WakeMission
        let difficulty: MissionDifficulty
        let seed: UInt64
        let canSnooze: Bool
    }

    enum Phase { case mission, awake }

    @Published var run: Run?
    @Published var phase: Phase = .mission
    private var lastArmed: Date?
    private var inApp = true

    private init() {}

    // MARK: Entry points

    /// "Start mission" tapped on the alarm.
    func missionRequested() {
        var state = WakeAlarmState.load()
        state.missionRequestedAt = Date()
        state.save()
        present(force: true)
    }

    /// "Stop" tapped on the alarm without doing the mission.
    func stoppedFromAlert() async {
        let now = Date()
        guard dueKey(now: now) != nil else { return }
        await WakeAlarmScheduler.ringAgain(at: WakeAlarmPlan.reRing(after: .stoppedWithoutMission, now: now),
                                           title: "Nice try. Start your mission")
    }

    func appBecameActive() {
        inApp = true
        let now = Date()
        let state = WakeAlarmState.load()
        // Opening the app once the wake-up check has asked answers it.
        if let ask = state.wakeCheckAt, now >= ask { WakeAlarmScheduler.cancelWakeCheck() }
        let requested = state.missionRequestedAt.map { now.timeIntervalSince($0) < 10 * 60 } ?? false
        present(force: requested)
    }

    /// Leaving mid-mission rings again almost straight away.
    func appLeft() {
        inApp = false
        guard run != nil, phase == .mission else { return }
        let now = Date()
        lastArmed = now
        Task { await WakeAlarmScheduler.ringAgain(at: WakeAlarmPlan.reRing(after: .leftApp, now: now),
                                                  title: "Come back and finish your mission") }
    }

    /// Any progress in the mission pushes the re-ring back out.
    func progress() {
        guard run != nil, phase == .mission else { return }
        let now = Date()
        guard WakeAlarmPlan.shouldExtend(lastArmed: lastArmed, now: now) else { return }
        lastArmed = now
        Task { await WakeAlarmScheduler.ringAgain(at: WakeAlarmPlan.reRing(after: .progress, now: now)) }
    }

    func complete() {
        guard let run else { return }
        var state = WakeAlarmState.load()
        if !state.completed.contains(run.id) { state.completed.append(run.id) }
        state.missionRequestedAt = nil
        state.snoozedUntil = nil
        state.save()
        WakeAlarmScheduler.cancelReRing()
        WakeAlarmScheduler.stopRinging()
        if WakeAlarmSettings.load().wakeCheck {
            Task { await WakeAlarmScheduler.scheduleWakeCheck() }
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { phase = .awake }
    }

    func snooze() {
        guard let run, run.canSnooze else { return }
        let settings = WakeAlarmSettings.load()
        var state = WakeAlarmState.load()
        state.snoozesUsed[run.id, default: 0] += 1
        let until = Date().addingTimeInterval(Double(settings.snoozeMinutes) * 60)
        state.snoozedUntil = until
        state.missionRequestedAt = nil
        state.save()
        Task { await WakeAlarmScheduler.ringAgain(at: until, title: "Snooze is over. Mission time") }
        self.run = nil
    }

    /// Close the "You're up" screen.
    func finish() {
        run = nil
        phase = .mission
    }

    // MARK: Pieces

    /// Stable across launches (unlike hashValue), so a mission doesn't change if the app restarts.
    private static func seed(_ key: String) -> UInt64 {
        key.utf8.reduce(1_469_598_103_934_665_603) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private func dueKey(now: Date) -> String? {
        let settings = WakeAlarmSettings.load()
        let state = WakeAlarmState.load()
        return WakeAlarmPlan.due(schedule: WakeSchedule.load(), extra: settings.extra,
                                 completed: Set(state.completed), snoozedUntil: state.snoozedUntil, now: now)
            .map { WakeAlarmPlan.key($0) }
    }

    private func present(force: Bool) {
        guard run == nil else { return }
        let now = Date()
        let settings = WakeAlarmSettings.load()
        guard settings.enabled || force else { return }
        guard let key = dueKey(now: now) ?? (force ? WakeAlarmPlan.key(now) : nil) else { return }
        let used = WakeAlarmState.load().snoozesUsed[key] ?? 0
        phase = .mission
        run = Run(id: key, mission: settings.effectiveMission, difficulty: settings.difficulty,
                  seed: Self.seed(key), canSnooze: used < settings.snoozes)
        // Starting the mission silences the alarm; stalling brings it back.
        WakeAlarmScheduler.stopRinging()
        lastArmed = now
        Task { await WakeAlarmScheduler.ringAgain(at: WakeAlarmPlan.reRing(after: .missionStarted, now: now)) }
    }
}

// MARK: - Hosting

extension View {
    /// Presents the wake-up mission over everything when an alarm needs it.
    func wakeMissionHost() -> some View { modifier(WakeMissionHost()) }
}

private struct WakeMissionHost: ViewModifier {
    @ObservedObject private var coordinator = WakeAlarmCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $coordinator.run) { run in
                WakeMissionScreen(run: run)
                    .interactiveDismissDisabled()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:     coordinator.appBecameActive()
                case .background: coordinator.appLeft()
                default:          break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wakeScheduleDidChange)) { _ in
                Task { await WakeAlarmScheduler.reschedule() }
            }
            .task {
                coordinator.appBecameActive()
                await WakeAlarmScheduler.reschedule()
            }
    }
}
