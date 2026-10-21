//
//  WeeklyReportService.swift
//  Dialed
//
//  Gathers both sides' week for WeeklyHeadToHeadReport, schedules the
//  Sunday 7 PM "Your week vs Dave is ready" notification, and sends the
//  finished report to the challenge server so it shows on Dave's page
//  (once per week; Monday catches up if Sunday was missed).
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
enum WeeklyReportService {

    nonisolated static let alertsKey = "weeklyReport.alerts"
    private static let notificationID = "weeklyReport.sunday"
    private static let postedKey = "weeklyReport.posted"
    private static let cacheKey = "weeklyReport.latest"

    private static var lastScheduled: Date?

    static var alertsOn: Bool { UserDefaults.standard.object(forKey: alertsKey) as? Bool ?? true }

    // MARK: - Build

    /// The report for the week containing `date` (so far, if it isn't over).
    static func build(weekOf date: Date = Date(), context: ModelContext) async -> WeeklyHeadToHeadReport.Report? {
        guard let challenge = WeightChallenge.load() else { return nil }
        let calendar = Calendar.current
        let weekStart = SideBets.weekStart(date, calendar: calendar)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }

        // Weights: a couple of weeks of runway so the trend has settled.
        let since = calendar.date(byAdding: .day, value: -21, to: weekStart) ?? weekStart
        let readings = await WeightDataSource.readings(context: context, since: min(since, challenge.startDate))
        let friendReadings = challenge.friendWeighIns.map { WeightReading(date: $0.date, pounds: $0.pounds, source: .manual) }
        let mine = WeeklyHeadToHeadReport.weekTrend(readings, weekStart: weekStart, calendar: calendar)
        let theirs = WeeklyHeadToHeadReport.weekTrend(friendReadings, weekStart: weekStart, calendar: calendar)

        var you = WeeklyHeadToHeadReport.SideWeek(startTrend: mine.start, endTrend: mine.end)
        you.steps = await SideBetsScorer.score(.steps, from: weekStart, to: weekEnd, context: context)
        you.miles = await SideBetsScorer.score(.miles, from: weekStart, to: weekEnd, context: context)
        you.workouts = await SideBetsScorer.score(.workouts, from: weekStart, to: weekEnd, context: context)
        you.prs = await SideBetsScorer.score(.prs, from: weekStart, to: weekEnd, context: context)
        you.xp = questXP(from: weekStart, to: weekEnd, calendar: calendar)

        var friend = WeeklyHeadToHeadReport.SideWeek(startTrend: theirs.start, endTrend: theirs.end)
        // Their stats card only describes the current week.
        if SideBets.weekStart(Date(), calendar: calendar) == weekStart, let stats = ChallengeSync.shared.other?.stats {
            friend.steps = stats.stepsAvg7.map { ($0 * 7).rounded() }
            friend.workouts = stats.workoutsWeek
        }

        // The week's side bet fills in whichever side's number it carries.
        let weekKey = SideBets.weekKey(weekStart, calendar: calendar)
        let bet = SideBetsStore.shared.bets.first { $0.week == weekKey && $0.status == .active }
        if let bet, let theirScore = bet.friendScore {
            switch bet.metric {
            case .steps:    friend.steps = theirScore
            case .miles:    friend.miles = theirScore
            case .workouts: friend.workouts = theirScore
            case .prs:      friend.prs = theirScore
            default: break
            }
        }

        let progress = WeightChallengeEngine.progress(challenge: challenge, readings: readings)
        let race = await RacePace.report(challenge: challenge, readings: readings, context: context)
        let inputs = WeeklyHeadToHeadReport.Inputs(
            weekStart: weekStart, challengeStart: challenge.startDate, scoring: challenge.scoring,
            friendName: challenge.friendDisplayName, you: you, friend: friend,
            yourStartWeight: progress.startWeight, friendStartWeight: progress.friend?.startWeight,
            bet: bet, raceStatus: race?.result.status, neededRate: race?.result.needed,
            leader: progress.leader, margin: progress.margin)
        let report = WeeklyHeadToHeadReport.build(inputs, calendar: calendar)
        cache(report)
        return report
    }

    /// Quest XP earned on days in the week (quests + sweep bonus).
    private static func questXP(from start: Date, to end: Date, calendar: Calendar) -> Double {
        let store = GameStore.load()
        var d = start, total = 0
        while d < end {
            if let day = store.days[WeeklyReview.dayKey(d, calendar: calendar)] {
                total += day.done.values.reduce(0, +) + (day.swept ? QuestEngine.sweepBonus : 0)
            }
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? end
        }
        return Double(total)
    }

    // MARK: - Delivery

    /// Sunday 7 PM, every week, while a challenge is on and the toggle is.
    static func scheduleReminder(force: Bool = false) async {
        if !force, let last = lastScheduled, Date().timeIntervalSince(last) < 3600 { return }
        lastScheduled = Date()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard alertsOn, let challenge = WeightChallenge.load(), challenge.endDate > Date() else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your week vs \(challenge.friendDisplayName) is ready"
        content.body = "Weight, steps, workouts and the side bet: see who took the week."
        content.sound = .default
        content.threadIdentifier = "dialed.headToHead"
        content.userInfo = [ReminderRoute.userInfoKey: ReminderRoute.weeklyReport.rawValue]
        var when = DateComponents()
        when.weekday = 1
        when.hour = 19
        when.minute = 0
        try? await center.add(UNNotificationRequest(
            identifier: notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }

    /// From Sunday 7 PM: this week's report goes to the server; Monday to
    /// Saturday: last week's, if it never went. Once per week.
    static func postIfDue(context: ModelContext, now: Date = Date()) async {
        guard ChallengeSync.shared.isLive else { return }
        let calendar = Calendar.current
        let isSundayEvening = calendar.component(.weekday, from: now) == 1 && calendar.component(.hour, from: now) >= 19
        let target = isSundayEvening ? now : calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let key = SideBets.weekKey(target, calendar: calendar)
        var posted = Set(UserDefaults.standard.stringArray(forKey: postedKey) ?? [])
        guard !posted.contains(key),
              let challenge = WeightChallenge.load(),
              SideBets.weekStart(challenge.startDate, calendar: calendar) <= SideBets.weekStart(target, calendar: calendar),
              let report = await build(weekOf: target, context: context) else { return }
        if await ChallengeSync.shared.postReport(report) {
            posted.insert(key)
            UserDefaults.standard.set(Array(Array(posted).sorted().suffix(30)), forKey: postedKey)
        }
    }

    // MARK: - Cache

    private static func cache(_ report: WeeklyHeadToHeadReport.Report) {
        if let data = try? JSONEncoder().encode(report) { UserDefaults.standard.set(data, forKey: cacheKey) }
    }

    static var cached: WeeklyHeadToHeadReport.Report? {
        UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(WeeklyHeadToHeadReport.Report.self, from: $0) }
    }
}
