//
//  HeadToHeadSync.swift
//  Dialed
//
//  Keeps the live challenge current without you opening it: on launch,
//  when the app comes forward, after anything is logged (so a new scale
//  reading publishes) and in background refresh. When your friend's new
//  weigh-in lands it says so ("Dave just weighed in · You're still ahead
//  by 1.2 lb"), and now and then a trash-talk nudge when the race moves.
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
enum HeadToHeadSync {

    nonisolated static let weighInAlertsKey = "h2h.weighInAlerts"
    nonisolated static let nudgesKey = "h2h.nudges"
    private static let snapshotKey = "h2h.snapshot"
    private static let sentKey = "h2h.nudgesSent"
    private static let idPrefix = "h2h_"

    static var weighInAlertsOn: Bool { UserDefaults.standard.object(forKey: weighInAlertsKey) as? Bool ?? true }
    static var nudgesOn: Bool { UserDefaults.standard.object(forKey: nudgesKey) as? Bool ?? true }

    private static var lastRun: Date?

    /// Publish your weigh-ins, pull your friend's, and tell you what
    /// changed. At most every 5 minutes unless `force`.
    static func run(context: ModelContext, force: Bool = false) async {
        let live = ChallengeSync.shared
        guard live.isLive, let challenge = WeightChallenge.load() else { return }
        let now = Date()
        if !force, let lastRun, now.timeIntervalSince(lastRun) < 300 { return }
        lastRun = now

        let calendar = Calendar.current
        let since = min(calendar.date(byAdding: .day, value: -7, to: challenge.startDate) ?? challenge.startDate,
                        calendar.startOfDay(for: now))
        let readings = await WeightDataSource.readings(context: context, since: since)
        await live.sync(readings: readings, force: true)
        // Side bets: publish your running number, hear about proposals and results.
        await SideBetsStore.shared.refresh(context: context)
        guard let updated = WeightChallenge.load() else { return }

        let progress = WeightChallengeEngine.progress(challenge: updated, readings: readings, now: now)
        let before = loadSnapshot()
        let after = HeadToHead.snapshot(progress, friendWeighIns: updated.friendWeighIns)
        defer { save(after) }

        // Backfilled old days aren't news; a weigh-in from the last 3 days is.
        let fresh = HeadToHead.newWeighIns(updated.friendWeighIns, since: before)
            .filter { now.timeIntervalSince($0.date) < 3 * 86_400 }
        let newest = fresh.last
        let prior = newest.flatMap { n in updated.friendWeighIns.filter { $0.date < n.date }.max { $0.date < $1.date } }

        guard await isAuthorized() else { return }
        let name = updated.friendDisplayName

        if weighInAlertsOn, let newest {
            let alert = HeadToHead.weighInAlert(friendName: name, scoring: updated.scoring, progress: progress,
                                                previousLeader: before?.leader, newest: newest, prior: prior)
            await post(id: "\(idPrefix)weighin_\(HeadToHead.key(newest))", title: alert.title, body: alert.body, at: nil)
        }

        if nudgesOn, let reason = HeadToHead.nudgeReason(before: before, after: after, newest: newest, prior: prior),
           let at = HeadToHead.nudgeTime(now: now, sent: sentDates) {
            let snapshot = HealthSnapshot.challenge(updated, progress)
            let line = await DialedAI.trashTalk(snapshot, tone: .savage) ?? HeadToHead.cannedLine(reason, friendName: name)
            await post(id: "\(idPrefix)nudge_\(Int(now.timeIntervalSince1970))",
                       title: HeadToHead.nudgeTitle(reason, friendName: name),
                       body: "Send \(name) this? \(line)", at: at > now ? at : nil)
            recordSent(at)
        }
    }

    // MARK: - Notifications

    private static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// `at` nil = now.
    private static func post(id: String, title: String, body: String, at: Date?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "dialed.headToHead"
        content.userInfo = [ReminderRoute.userInfoKey: ReminderRoute.challenge.rawValue]
        let trigger: UNNotificationTrigger
        if let at {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Storage

    private static func loadSnapshot() -> HeadToHead.Snapshot? {
        UserDefaults.standard.data(forKey: snapshotKey).flatMap { try? JSONDecoder().decode(HeadToHead.Snapshot.self, from: $0) }
    }

    private static func save(_ snapshot: HeadToHead.Snapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: snapshotKey) }
    }

    private static var sentDates: [Date] {
        (UserDefaults.standard.array(forKey: sentKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    private static func recordSent(_ date: Date) {
        let keep = (sentDates + [date]).filter { $0 > Date().addingTimeInterval(-14 * 86_400) }
        UserDefaults.standard.set(keep.map(\.timeIntervalSince1970), forKey: sentKey)
    }
}

extension HealthSnapshot {
    /// The challenge numbers the trash-talk writer gets (same as the Challenge tab's card).
    static func challenge(_ c: WeightChallenge, _ p: WeightChallengeEngine.Progress) -> HealthSnapshot {
        var s = HealthSnapshot()
        s.firstName = UserDefaults.standard.string(forKey: "user.firstName") ?? ""
        s.friendName = c.friendDisplayName
        s.challengeDay = p.dayNumber
        s.challengeDays = p.totalDays
        s.daysLeft = p.daysLeft
        s.scoring = c.scoring
        if p.startWeight != nil && p.currentWeight != nil {
            s.lostLbs = p.lostLbs
            s.lostPercent = p.lostPercent
        }
        s.friendLostLbs = p.friend?.lostLbs
        s.friendLostPercent = p.friend?.lostPercent
        s.leader = p.leader
        s.margin = p.margin
        s.goalLossLbs = p.goalLossLbs
        s.weighedInToday = p.weighedInToday
        return s
    }
}
