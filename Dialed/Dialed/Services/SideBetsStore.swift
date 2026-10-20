//
//  SideBetsStore.swift
//  Dialed
//
//  Side bets on this phone: with a live challenge (and an updated
//  server) they live on the server, so your friend proposes, accepts and
//  posts their own number from the invite page; otherwise they're kept
//  here and you type your friend's number in. Your own number is worked
//  out from your data (steps, miles, workouts, PRs, skipped days, protein
//  days) and published as the week goes. Tells you when a bet is
//  proposed, accepted or settled.
//

import Foundation
import SwiftData
import HealthKit
import UserNotifications

@MainActor
final class SideBetsStore: ObservableObject {
    static let shared = SideBetsStore()

    nonisolated static let alertsKey = "sideBets.alerts"
    private static let localKey = "sideBets.local"
    private static let manualKey = "sideBets.friendManual"
    private static let seenKey = "sideBets.seen"
    private static let announcedKey = "sideBets.announced"

    @Published private(set) var bets: [SideBets.Bet] = []
    @Published private(set) var isWorking = false
    @Published var lastError: String?

    private init() {
        bets = assembled()
    }

    // MARK: - Reading

    /// Bets go through the server when the challenge is live and the
    /// server knows about bets; otherwise they stay on this phone.
    var usesServer: Bool { ChallengeSync.shared.isLive && ChallengeSync.shared.state?.bets != nil }

    var friendName: String { WeightChallenge.load()?.friendDisplayName ?? "Your friend" }
    var current: SideBets.Bet? { SideBets.current(bets, now: Date()) }
    var ledger: SideBets.Ledger { SideBets.ledger(bets, now: Date()) }

    struct Result: Identifiable {
        let bet: SideBets.Bet
        let winner: SideBets.Side
        var id: String { bet.id }
    }

    /// Finished bets with a result, newest first.
    var history: [Result] {
        let now = Date()
        return bets.sorted { $0.week > $1.week }.compactMap { b in
            SideBets.winner(b, now: now).map { Result(bet: b, winner: $0) }
        }
    }

    /// Active bets from a finished week still waiting on a number.
    var awaitingScores: [SideBets.Bet] {
        let now = Date()
        return bets.filter { $0.status == .active && SideBets.isOver($0, now: now) && SideBets.winner($0, now: now) == nil }
    }

    private func assembled() -> [SideBets.Bet] {
        var list: [SideBets.Bet]
        if usesServer, let state = ChallengeSync.shared.state {
            list = (state.bets ?? []).compactMap { SideBets.bet(from: $0, role: state.role) }
        } else {
            list = localBets
        }
        let manual = manualScores
        for i in list.indices where list[i].friendScore == nil {
            list[i].friendScore = manual[list[i].id]
        }
        return list
    }

    // MARK: - Refresh

    /// Work out your numbers for running bets, publish them, and tell you
    /// what changed. Runs with the head-to-head sync and when the
    /// Challenge tab opens.
    func refresh(context: ModelContext) async {
        let now = Date()
        for bet in assembled() where bet.status == .active {
            guard let start = ChallengeWire.date(fromKey: bet.week), let end = SideBets.weekEnd(bet.week),
                  start <= now, now.timeIntervalSince(end) < 2 * 86_400 else { continue }
            let score = await SideBetsScorer.score(bet.metric, from: start, to: min(end, now), context: context)
            if score != bet.youScore { await setYourScore(bet, score) }
        }
        bets = assembled()
        await announce(now: now)
    }

    private func setYourScore(_ bet: SideBets.Bet, _ score: Double) async {
        if usesServer {
            await ChallengeSync.shared.updateBet(id: bet.id, score: score)
        } else {
            updateLocal(bet.id) { $0.youScore = score }
        }
    }

    // MARK: - Actions

    func propose(metric: SideBets.Metric, stake: String, context: ModelContext) async {
        let stake = stake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? SideBets.presets[0] : stake
        let week = SideBets.weekKey(Date())
        isWorking = true
        defer { isWorking = false }
        if usesServer {
            if !(await ChallengeSync.shared.proposeBet(week: week, metric: metric, stake: stake)) {
                lastError = ChallengeSync.shared.lastError
                return
            }
        } else {
            // Offline: you shook on it in person, so it starts right away.
            var list = localBets
            list.append(SideBets.Bet(id: UUID().uuidString, week: week, metric: metric, stake: stake,
                                     proposer: .you, status: .active))
            localBets = list
        }
        lastError = nil
        await refresh(context: context)
    }

    func respond(_ bet: SideBets.Bet, accept: Bool, context: ModelContext) async {
        guard usesServer else { return }
        isWorking = true
        defer { isWorking = false }
        await ChallengeSync.shared.updateBet(id: bet.id, action: accept ? "accept" : "decline")
        await refresh(context: context)
    }

    func cancel(_ bet: SideBets.Bet) async {
        if usesServer {
            await ChallengeSync.shared.updateBet(id: bet.id, action: "cancel")
        } else {
            updateLocal(bet.id) { $0.status = .cancelled }
        }
        bets = assembled()
    }

    func setPaid(_ bet: SideBets.Bet, _ paid: Bool) async {
        if usesServer {
            await ChallengeSync.shared.updateBet(id: bet.id, action: paid ? "paid" : "unpaid")
        } else {
            updateLocal(bet.id) { $0.paid = paid }
        }
        bets = assembled()
    }

    /// Your friend's number, typed in (until their side posts its own).
    func setFriendScore(_ bet: SideBets.Bet, _ value: Double?) {
        var manual = manualScores
        manual[bet.id] = value
        manualScores = manual
        bets = assembled()
    }

    // MARK: - Notifications

    static var alertsOn: Bool { UserDefaults.standard.object(forKey: alertsKey) as? Bool ?? true }

    private func announce(now: Date) async {
        let old = seenBets
        seenBets = bets
        var announced = announcedIDs
        guard let old else {
            // First look: what's already settled isn't news.
            announcedIDs = Set(bets.filter { SideBets.isSettled($0, now: now) }.map(\.id))
            return
        }
        // Give both sides half a day after Sunday to post final numbers.
        let events = SideBets.events(old: old, new: bets, announced: announced, now: now).filter { e in
            guard case .settled(let b, _) = e else { return true }
            return (SideBets.weekEnd(b.week).map { now.timeIntervalSince($0) >= 12 * 3600 }) ?? false
        }
        for case .settled(let b, _) in events { announced.insert(b.id) }
        announcedIDs = announced
        guard Self.alertsOn, !events.isEmpty else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let name = friendName
        for event in events {
            let alert = SideBets.alert(event, friendName: name)
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.threadIdentifier = "dialed.headToHead"
            content.userInfo = [ReminderRoute.userInfoKey: ReminderRoute.challenge.rawValue]
            let id = "sidebet_\(Self.eventKey(event))"
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        }
    }

    private static func eventKey(_ e: SideBets.Event) -> String {
        switch e {
        case .proposed(let b):   return "proposed_\(b.id)"
        case .accepted(let b):   return "accepted_\(b.id)"
        case .declined(let b):   return "declined_\(b.id)"
        case .settled(let b, _): return "settled_\(b.id)"
        }
    }

    // MARK: - Storage

    private var localBets: [SideBets.Bet] {
        get { decode([SideBets.Bet].self, Self.localKey) ?? [] }
        set { encode(Array(newValue.suffix(60)), Self.localKey) }
    }

    private var manualScores: [String: Double] {
        get { decode([String: Double].self, Self.manualKey) ?? [:] }
        set { encode(newValue, Self.manualKey) }
    }

    private var seenBets: [SideBets.Bet]? {
        get { decode([SideBets.Bet].self, Self.seenKey) }
        set { encode(newValue, Self.seenKey) }
    }

    private var announcedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.announcedKey) ?? []) }
        set { UserDefaults.standard.set(Array(Array(newValue).suffix(100)), forKey: Self.announcedKey) }
    }

    private func updateLocal(_ id: String, _ change: (inout SideBets.Bet) -> Void) {
        var list = localBets
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        localBets = list
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Your number

/// Your total for a metric over part of a week, from what Dialed already knows.
@MainActor
enum SideBetsScorer {

    static func score(_ metric: SideBets.Metric, from start: Date, to end: Date, context: ModelContext) async -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var days: [Date] = []
        var d = calendar.startOfDay(for: start)
        while d < end, d <= today {
            days.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? end
        }
        guard !days.isEmpty else { return 0 }
        let doneDays = Set((UserDefaults.standard.string(forKey: WorkoutPlanStore.doneKey) ?? "")
            .split(separator: ",").map(String.init))

        switch metric {
        case .steps:
            let back = (calendar.dateComponents([.day], from: days[0], to: today).day ?? 0) + 1
            let sums = (try? await HealthKitManager.shared.fetchDailySums(.stepCount, unit: .count(), days: back)) ?? [:]
            return days.reduce(0) { $0 + (sums[$1] ?? 0) }.rounded()

        case .miles:
            let byDay = MileHistory.load()?.milesByDay ?? [:]
            let total = days.reduce(0) { $0 + (byDay[$1] ?? 0) }
            return (total * 10).rounded() / 10

        case .workouts:
            return Double(days.filter { doneDays.contains(WorkoutPlanStore.key($0)) }.count)

        case .prs:
            let all = PlanWorkoutLogStore.allSets(context: context).filter(\.completed).map {
                StrengthMilestones.SetRecord(exercise: $0.exerciseName, date: calendar.startOfDay(for: $0.date),
                                             weight: $0.weightLbs, reps: $0.reps)
            }
            return Double(days.reduce(0) { total, day in
                let session = all.filter { $0.date == day }
                guard !session.isEmpty else { return total }
                return total + StrengthMilestones.prs(session: session, history: all.filter { $0.date < day }).count
            })

        case .skippedDays:
            // Only finished days can be skipped; rest days never count.
            return Double(days.filter { day in
                day < today && WorkoutPlanStore.session(on: day).kind != .rest
                    && !doneDays.contains(WorkoutPlanStore.key(day))
            }.count)

        case .proteinDays:
            let target = UserSettings.load().proteinTargetGrams
            guard target > 0 else { return 0 }
            return Double(days.filter { day in
                FoodLog.entries(on: day, context: context).reduce(0) { $0 + $1.protein } >= target
            }.count)
        }
    }
}
