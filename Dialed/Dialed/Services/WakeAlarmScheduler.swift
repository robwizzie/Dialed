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
//  All scheduling work runs one piece at a time (`serially`) and writes
//  back only the fields it owns, so overlapping triggers (launch,
//  foreground, a settings change, a tap mid-mission) can't leave duplicate
//  or orphaned alarms behind.
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

/// One wake-up alarm Dialed armed: upcoming, or rung recently.
struct ArmedAlarm: Codable, Equatable {
    /// AlarmKit ID; nil on the notification fallback.
    var id: String?
    var fireAt: Date
    /// Mission icon + sound it was armed with; a change re-arms it.
    var signature: String
}

/// What the alarm system has scheduled and what's been beaten.
struct WakeAlarmState: Codable, Equatable {
    /// AlarmKit IDs from older versions (before `armed`); cancelled on the next reschedule.
    var scheduledIDs: [String] = []
    /// Wake-up alarms armed. Only these can ask for a mission, so a time
    /// that passed without an alarm (alarms were off, the time was moved)
    /// never does.
    var armed: [ArmedAlarm] = []
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
        let cutoff = Date().addingTimeInterval(-WakeAlarmPlan.armedMemory)
        copy.armed = copy.armed.filter { $0.fireAt > cutoff }
        if copy.snoozesUsed.count > 30 {
            let recent = Set(copy.completed.suffix(30))
            copy.snoozesUsed = copy.snoozesUsed.filter { recent.contains($0.key) }
        }
        if let data = try? JSONEncoder().encode(copy) { defaults.set(data, forKey: Self.key) }
    }

    /// Load, change, save in one go (no awaits in between).
    @discardableResult
    static func update(_ change: (inout WakeAlarmState) -> Void) -> WakeAlarmState {
        var s = load()
        change(&s)
        s.save()
        return s
    }
}

extension WakeAlarmState {
    private enum CodingKeys: String, CodingKey {
        case scheduledIDs, armed, reRingID, reRingAt, wakeCheckAt, wakeCheckID, completed, snoozedUntil,
             snoozesUsed, missionRequestedAt
    }

    /// Missing fields keep their defaults, so older saves still load.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scheduledIDs = try c.decodeIfPresent([String].self, forKey: .scheduledIDs) ?? []
        armed = (try? c.decodeIfPresent([ArmedAlarm].self, forKey: .armed)) ?? []
        reRingID = try c.decodeIfPresent(String.self, forKey: .reRingID)
        reRingAt = try c.decodeIfPresent(Date.self, forKey: .reRingAt)
        wakeCheckAt = try c.decodeIfPresent(Date.self, forKey: .wakeCheckAt)
        wakeCheckID = try c.decodeIfPresent(String.self, forKey: .wakeCheckID)
        completed = try c.decodeIfPresent([String].self, forKey: .completed) ?? []
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        snoozesUsed = try c.decodeIfPresent([String: Int].self, forKey: .snoozesUsed) ?? [:]
        missionRequestedAt = try c.decodeIfPresent(Date.self, forKey: .missionRequestedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scheduledIDs, forKey: .scheduledIDs)
        try c.encode(armed, forKey: .armed)
        try c.encodeIfPresent(reRingID, forKey: .reRingID)
        try c.encodeIfPresent(reRingAt, forKey: .reRingAt)
        try c.encodeIfPresent(wakeCheckAt, forKey: .wakeCheckAt)
        try c.encodeIfPresent(wakeCheckID, forKey: .wakeCheckID)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(snoozedUntil, forKey: .snoozedUntil)
        try c.encode(snoozesUsed, forKey: .snoozesUsed)
        try c.encodeIfPresent(missionRequestedAt, forKey: .missionRequestedAt)
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

/// Whether Dialed may ring.
enum AlarmPermission { case allowed, denied, notAsked }

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

    // MARK: Permission

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

    /// Current permission, without asking.
    static func permission() async -> AlarmPermission {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized:    return .allowed
            case .denied:        return .denied
            case .notDetermined: return .notAsked
            @unknown default:    return .notAsked
            }
        }
        #endif
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied:                              return .denied
        default:                                   return .notAsked
        }
    }

    // MARK: Serial work

    private static var tail: Task<Void, Never>?

    /// Runs `work` after everything queued before it.
    private static func serially(_ work: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        tail = task
        await task.value
    }

    // MARK: Wake-ups

    /// Bring the next week of wake-up alarms in line with the schedule and
    /// settings: keep what's already right, cancel what isn't, add what's
    /// missing. Safe to call often (launch, foreground, any change).
    static func reschedule() async {
        await serially { await performReschedule(now: Date()) }
    }

    private static func performReschedule(now: Date) async {
        let settings = WakeAlarmSettings.load()
        let start = WakeAlarmState.load()
        cancelIfNotRinging(ids: start.scheduledIDs)

        guard settings.enabled else {
            // Off means off: nothing upcoming, nothing to chase.
            cancel(ids: start.armed.filter { $0.fireAt > now }.compactMap(\.id))
            cancel(ids: [start.reRingID, start.wakeCheckID].compactMap { $0 })
            await removePending(prefix: mainPrefix)
            await removePending(prefix: reRingPrefix)
            await removePending(prefix: checkPrefix)
            cancelOrphans(keeping: [])
            WakeAlarmState.update {
                $0.scheduledIDs = []
                $0.armed = []
                $0.reRingID = nil; $0.reRingAt = nil
                $0.wakeCheckID = nil; $0.wakeCheckAt = nil
                $0.snoozedUntil = nil
                $0.missionRequestedAt = nil
            }
            return
        }

        let soundName = await AlarmSoundLibrary.prepared(settings.sound, ramp: settings.soundRamp)
        let summary = settings.effectiveMission
        let signature = "\(summary.symbol)|\(soundName ?? "default")"
        let dates = WakeAlarmPlan.fireDates(schedule: WakeSchedule.load(), extra: settings.extra, from: now)

        // Ones that already rang stay remembered so `due` can still ask for their mission.
        var armed = start.armed.filter { $0.fireAt <= now }

        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let wanted = Set(dates.map { WakeAlarmPlan.key($0) })
            for a in start.armed where a.fireAt > now {
                if a.id != nil, a.signature == signature, wanted.contains(WakeAlarmPlan.key(a.fireAt)) {
                    armed.append(a)
                } else {
                    cancel(ids: a.id.map { [$0] } ?? [])
                }
            }
            let have = Set(armed.filter { $0.fireAt > now }.map { WakeAlarmPlan.key($0.fireAt) })
            for date in dates where !have.contains(WakeAlarmPlan.key(date)) {
                if let id = await scheduleAlarm(at: date, title: "Time to get up", symbol: summary.symbol,
                                                mission: summary.single?.rawValue ?? "random", sound: soundName) {
                    armed.append(ArmedAlarm(id: id.uuidString, fireAt: date, signature: signature))
                }
            }
            let fresh = WakeAlarmState.load()
            cancelOrphans(keeping: Set(armed.compactMap(\.id) + [fresh.reRingID, fresh.wakeCheckID].compactMap { $0 }))
            WakeAlarmState.update {
                $0.scheduledIDs = []
                $0.armed = armed.sorted { $0.fireAt < $1.fireAt }
            }
            return
        }
        #endif

        // Fallback: six nudges a minute apart (the notification limit is 64).
        await removePending(prefix: mainPrefix)
        // Without permission nothing would ring, so nothing is armed either.
        let allowed = await permission() == .allowed
        for date in dates.prefix(allowed ? 8 : 0) {
            for minute in 0..<6 {
                await notify(id: "\(mainPrefix)\(WakeAlarmPlan.key(date))_\(minute)",
                             title: minute == 0 ? "⏰ Time to get up" : "⏰ Still ringing",
                             body: "Open Dialed and finish your \(summary.title.lowercased()) mission to stop it.",
                             at: date.addingTimeInterval(Double(minute) * 60), sound: soundName)
            }
            armed.append(ArmedAlarm(id: nil, fireAt: date, signature: signature))
        }
        WakeAlarmState.update {
            $0.scheduledIDs = []
            $0.armed = armed.sorted { $0.fireAt < $1.fireAt }
        }
    }

    /// The fallback's remaining "still ringing" nudges for the alarm at `key`
    /// (the mission has started, or it's done).
    static func silenceNudges(key: String) async {
        await serially { await removePending(prefix: "\(mainPrefix)\(key)") }
    }

    // MARK: Re-rings

    /// Ring again at `date` (replaces any pending re-ring). Skipped if
    /// `onlyIf` is false by the time it runs, so a re-ring queued just
    /// before the mission finished can't sneak in after it.
    static func ringAgain(at date: Date, title: String = "Still in bed? Finish your mission",
                          onlyIf: @escaping @MainActor () -> Bool = { true }) async {
        await serially {
            guard onlyIf() else { return }
            let old = WakeAlarmState.load().reRingID
            cancel(ids: old.map { [$0] } ?? [])
            await removePending(prefix: reRingPrefix)
            let id = await armOne(at: date, title: title, prefix: reRingPrefix)
            WakeAlarmState.update {
                $0.reRingID = id
                $0.reRingAt = date
            }
        }
    }

    static func cancelReRing() async {
        await serially {
            cancel(ids: WakeAlarmState.load().reRingID.map { [$0] } ?? [])
            await removePending(prefix: reRingPrefix)
            WakeAlarmState.update {
                $0.reRingID = nil
                $0.reRingAt = nil
            }
        }
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

    // MARK: Wake-up check

    /// A nudge after `wakeCheckDelay`, and the alarm again if it isn't answered.
    static func scheduleWakeCheck(now: Date = Date()) async {
        await serially {
            let ask = now.addingTimeInterval(WakeAlarmPlan.wakeCheckDelay)
            cancel(ids: WakeAlarmState.load().wakeCheckID.map { [$0] } ?? [])
            await removePending(prefix: checkPrefix)
            await notify(id: "\(checkPrefix)ask", title: "Still up? 👀",
                         body: "Open Dialed within 2 minutes or your alarm rings again.", at: ask, sound: nil)
            let id = await armOne(at: ask.addingTimeInterval(WakeAlarmPlan.wakeCheckWindow),
                                  title: "Wake-up check missed", prefix: checkPrefix)
            WakeAlarmState.update {
                $0.wakeCheckID = id
                $0.wakeCheckAt = ask
            }
        }
    }

    static func cancelWakeCheck() async {
        await serially {
            cancel(ids: WakeAlarmState.load().wakeCheckID.map { [$0] } ?? [])
            await removePending(prefix: checkPrefix)
            WakeAlarmState.update {
                $0.wakeCheckID = nil
                $0.wakeCheckAt = nil
            }
        }
    }

    // MARK: - Pieces

    /// One alarm (AlarmKit) or a short burst of notifications (fallback).
    private static func armOne(at date: Date, title: String, prefix: String) async -> String? {
        let settings = WakeAlarmSettings.load()
        let summary = settings.effectiveMission
        let soundName = await AlarmSoundLibrary.prepared(settings.sound, ramp: settings.soundRamp)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await scheduleAlarm(at: max(date, Date().addingTimeInterval(2)), title: title, symbol: summary.symbol,
                                       mission: summary.single?.rawValue ?? "random", sound: soundName)?.uuidString
        }
        #endif
        for i in 0..<3 {
            await notify(id: "\(prefix)\(Int(date.timeIntervalSince1970))_\(i)", title: "⏰ \(title)",
                         body: "Open Dialed and finish your \(summary.title.lowercased()) mission.",
                         at: max(date, Date().addingTimeInterval(2)).addingTimeInterval(Double(i) * 30), sound: soundName)
        }
        return nil
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func scheduleAlarm(at date: Date, title: String, symbol: String, mission: String,
                                      sound: String?) async -> UUID? {
        let id = UUID()
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(text: "Start mission", textColor: .black, systemImageName: symbol),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes<DialedAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: DialedAlarmMetadata(mission: mission),
            tintColor: Neka.green)
        let configuration = AlarmManager.AlarmConfiguration<DialedAlarmMetadata>(
            countdownDuration: nil,
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: StopWakeAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: StartWakeMissionIntent(alarmID: id.uuidString),
            sound: sound.map { AlertConfiguration.AlertSound.named($0) } ?? .default)
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

    /// Cancels `ids` unless one is ringing right now (it gets its mission first).
    private static func cancelIfNotRinging(ids: [String]) {
        guard !ids.isEmpty else { return }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let ringing = Set(((try? AlarmManager.shared.alarms) ?? []).filter { $0.state == .alerting }.map(\.id.uuidString))
            cancel(ids: ids.filter { !ringing.contains($0) })
        }
        #endif
    }

    /// Any scheduled AlarmKit alarm Dialed no longer tracks (a lost save, an
    /// older version) is cancelled, so nothing rings twice or unexpectedly.
    private static func cancelOrphans(keeping known: Set<String>) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for alarm in (try? AlarmManager.shared.alarms) ?? []
            where alarm.state == .scheduled && !known.contains(alarm.id.uuidString) {
                try? AlarmManager.shared.cancel(id: alarm.id)
            }
        }
        #endif
    }

    private static func notify(id: String, title: String, body: String, at date: Date, sound: String?) async {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
        content.interruptionLevel = .timeSensitive
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Awaited, so new requests added right after aren't swept up by a late removal.
    private static func removePending(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
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

/// The mission flow: present it when an alarm rang and still needs its
/// mission, keep a re-ring armed while you're at it, and run the wake-up
/// check after.
@MainActor
final class WakeAlarmCoordinator: ObservableObject {
    static let shared = WakeAlarmCoordinator()

    struct Run: Identifiable, Equatable {
        let id: String
        let mission: WakeMission
        /// Options for this run (already made harder after snoozes).
        let tuning: MissionTuning
        let seed: UInt64
        let canSnooze: Bool
        let snoozeLabel: String
        let wakeCheck: Bool
        /// A try-out from settings: nothing rings, nothing is recorded, and
        /// you can leave whenever you like.
        let isTest: Bool

        var difficulty: MissionDifficulty { tuning.difficulty(for: mission) }

        /// A try-out of `mission`, or of the alarm as configured (random pick,
        /// snooze button) when nil.
        static func test(_ mission: WakeMission?, settings: WakeAlarmSettings = .load()) -> Run {
            let seed = UInt64.random(in: 1...UInt64.max)
            let picked = mission ?? settings.mission(seed: seed)
            return Run(id: "test-\(seed)", mission: picked, tuning: settings.tuning, seed: seed,
                       canSnooze: mission == nil && settings.snoozeEnabled, snoozeLabel: settings.snoozeLabel(used: 0),
                       wakeCheck: false, isTest: true)
        }
    }

    enum Phase { case mission, awake }

    @Published var run: Run?
    @Published var phase: Phase = .mission
    private var lastArmed: Date?

    private init() {}

    // MARK: Entry points

    /// "Start mission" tapped on the alarm.
    func missionRequested() {
        WakeAlarmState.update { $0.missionRequestedAt = Date() }
        present(force: true)
    }

    /// "Stop" tapped on the alarm without doing the mission.
    func stoppedFromAlert() async {
        let now = Date()
        guard dueKey(now: now) != nil else { return }
        await WakeAlarmScheduler.ringAgain(at: WakeAlarmPlan.reRing(after: .stoppedWithoutMission, now: now),
                                           title: "Nice try. Start your mission",
                                           onlyIf: { [weak self] in self?.dueKey(now: Date()) != nil })
    }

    func appBecameActive() {
        let now = Date()
        let state = WakeAlarmState.load()
        // Opening the app once the wake-up check has asked answers it.
        if let ask = state.wakeCheckAt, now >= ask { Task { await WakeAlarmScheduler.cancelWakeCheck() } }
        let requested = state.missionRequestedAt.map { abs(now.timeIntervalSince($0)) < 10 * 60 } ?? false
        present(force: requested)
        // Keeps the rolling week of alarms topped up and in the current time zone.
        Task { await WakeAlarmScheduler.reschedule() }
    }

    /// Leaving mid-mission rings again almost straight away.
    func appLeft() {
        guard let run, !run.isTest, phase == .mission else { return }
        let now = Date()
        lastArmed = now
        Task {
            await WakeAlarmScheduler.ringAgain(at: WakeAlarmPlan.reRing(after: .leftApp, now: now),
                                               title: "Come back and finish your mission",
                                               onlyIf: { self.isMidMission(run.id) })
        }
    }

    /// Any progress in the mission pushes the re-ring back out.
    func progress() {
        guard let run, !run.isTest, phase == .mission else { return }
        let now = Date()
        guard WakeAlarmPlan.shouldExtend(lastArmed: lastArmed, now: now) else { return }
        lastArmed = now
        Task {
            await WakeAlarmScheduler.ringAgain(at: WakeAlarmPlan.reRing(after: .progress, now: now),
                                               onlyIf: { self.isMidMission(run.id) })
        }
    }

    func complete() {
        guard let run, !run.isTest else { return }
        let now = Date()
        WakeAlarmState.update { s in
            // Beating the mission answers every alarm that has rung, so an
            // older one in the window can't ask again.
            let rung = s.armed.filter { $0.fireAt <= now }.map { WakeAlarmPlan.key($0.fireAt) }
            for key in [run.id] + rung where !s.completed.contains(key) { s.completed.append(key) }
            s.missionRequestedAt = nil
            s.snoozedUntil = nil
        }
        WakeAlarmScheduler.stopRinging()
        let wakeCheck = run.wakeCheck
        Task {
            await WakeAlarmScheduler.cancelReRing()
            await WakeAlarmScheduler.silenceNudges(key: run.id)
            if wakeCheck { await WakeAlarmScheduler.scheduleWakeCheck() }
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { phase = .awake }
    }

    func snooze() {
        guard let run, !run.isTest, run.canSnooze else { return }
        let settings = WakeAlarmSettings.load()
        let until = Date().addingTimeInterval(Double(settings.snoozeMinutes) * 60)
        WakeAlarmState.update {
            $0.snoozesUsed[run.id, default: 0] += 1
            $0.snoozedUntil = until
            $0.missionRequestedAt = nil
        }
        WakeAlarmScheduler.stopRinging()
        Task {
            await WakeAlarmScheduler.silenceNudges(key: run.id)
            await WakeAlarmScheduler.ringAgain(at: until, title: "Snooze is over. Mission time",
                                               onlyIf: {
                                                   // Still this snooze (not answered or replaced since).
                                                   guard let s = WakeAlarmState.load().snoozedUntil else { return false }
                                                   return abs(s.timeIntervalSince(until)) < 1
                                               })
        }
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

    private func isMidMission(_ id: String) -> Bool {
        run?.id == id && phase == .mission
    }

    private func dueKey(now: Date) -> String? {
        let state = WakeAlarmState.load()
        return WakeAlarmPlan.due(armed: state.armed.map(\.fireAt), completed: Set(state.completed),
                                 snoozedUntil: state.snoozedUntil, now: now)
            .map { WakeAlarmPlan.key($0) }
    }

    private func present(force: Bool) {
        guard run == nil else { return }
        let now = Date()
        let settings = WakeAlarmSettings.load()
        guard settings.enabled || force else { return }
        // Only an alarm that actually rang (or "Start mission" on one) asks
        // for a mission. Never a wake-up time that passed while alarms were off.
        guard let key = dueKey(now: now) ?? (force ? WakeAlarmPlan.key(now) : nil) else { return }
        let used = WakeAlarmState.load().snoozesUsed[key] ?? 0
        let seed = Self.seed(key)
        let mission = settings.mission(seed: seed)
        let isOneOff = settings.extra.contains { WakeAlarmPlan.key($0) == key }
        phase = .mission
        run = Run(id: key, mission: mission,
                  tuning: settings.tuning.harder(by: settings.snoozeHarder ? used : 0, for: mission),
                  seed: seed &+ UInt64(used), canSnooze: settings.canSnooze(used: used),
                  snoozeLabel: settings.snoozeLabel(used: used),
                  wakeCheck: settings.wakeCheck && !isOneOff, isTest: false)
        // Starting the mission silences the alarm; stalling brings it back.
        WakeAlarmScheduler.stopRinging()
        lastArmed = now
        Task {
            await WakeAlarmScheduler.silenceNudges(key: key)
            await WakeAlarmScheduler.ringAgain(at: WakeAlarmPlan.reRing(after: .missionStarted, now: now),
                                               onlyIf: { self.isMidMission(key) })
        }
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
            // Fixed-time alarms follow the clock: travel or a manual clock change re-arms them.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                Task { await WakeAlarmScheduler.reschedule() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                Task { await WakeAlarmScheduler.reschedule() }
            }
            .task { coordinator.appBecameActive() }
    }
}
