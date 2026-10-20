//
//  SideBets.swift
//  Dialed
//
//  Weekly mini-battles on top of the main race: one metric for one week
//  (Mon–Sun) — most steps, most miles, most workouts, most PRs, fewest
//  skipped days, most protein days — with a stake ("Loser buys wings").
//  A bet is proposed, accepted (or declined), runs the week with both
//  sides' running totals, and settles into a ledger of who owes what.
//  Pure Foundation, tested; sync and scoring live in SideBetsStore.
//

import Foundation

enum SideBets {

    // MARK: - Metrics

    enum Metric: String, Codable, CaseIterable, Identifiable {
        case steps, miles, workouts, prs, skippedDays, proteinDays

        var id: String { rawValue }

        var title: String {
            switch self {
            case .steps:       return "Most steps"
            case .miles:       return "Most miles"
            case .workouts:    return "Most workouts"
            case .prs:         return "Most PRs"
            case .skippedDays: return "Fewest skipped days"
            case .proteinDays: return "Most protein days"
            }
        }

        var symbol: String {
            switch self {
            case .steps:       return "shoeprints.fill"
            case .miles:       return "figure.walk"
            case .workouts:    return "dumbbell.fill"
            case .prs:         return "trophy.fill"
            case .skippedDays: return "calendar.badge.exclamationmark"
            case .proteinDays: return "bolt.heart.fill"
            }
        }

        /// "12,480 steps", "6.2 mi", "3 workouts"…
        func format(_ value: Double) -> String {
            switch self {
            case .steps:       return "\(Int(value.rounded()).formatted()) steps"
            case .miles:       return String(format: "%.1f mi", value)
            case .workouts:    return plural(value, "workout")
            case .prs:         return plural(value, "PR")
            case .skippedDays: return plural(value, "skipped day")
            case .proteinDays: return plural(value, "protein day")
            }
        }

        /// Just the number, for bars and inputs.
        func number(_ value: Double) -> String {
            switch self {
            case .steps: return Int(value.rounded()).formatted()
            case .miles: return String(format: "%.1f", value)
            default:     return "\(Int(value.rounded()))"
            }
        }

        var higherWins: Bool { self != .skippedDays }

        private func plural(_ v: Double, _ word: String) -> String {
            let n = Int(v.rounded())
            return "\(n) \(word)\(n == 1 ? "" : "s")"
        }
    }

    // MARK: - Bets

    enum Side: String, Codable, Equatable { case you, friend, tie }

    enum Status: String, Codable, Equatable {
        case proposed, active, declined, cancelled
    }

    struct Bet: Codable, Identifiable, Equatable {
        var id: String
        /// Monday of the bet's week, "yyyy-MM-dd".
        var week: String
        var metric: Metric
        var stake: String
        var proposer: Side
        var status: Status
        var youScore: Double?
        var friendScore: Double?
        var paid: Bool = false
        var createdAt: Date = Date()
    }

    /// Ready-made stakes; any text works.
    static let presets = [
        "Loser buys wings 🍗",
        "Loser does 50 burpees",
        "Loser buys coffee for a week ☕️",
        "Loser picks the next cheat meal",
        "Loser posts a gym selfie 📸",
        "Loser buys the next round 🍺"
    ]

    // MARK: - Weeks

    static func mondayCalendar(_ calendar: Calendar) -> Calendar {
        var c = calendar
        c.firstWeekday = 2
        return c
    }

    /// Monday 00:00 of the week containing `date`.
    static func weekStart(_ date: Date, calendar: Calendar = .current) -> Date {
        let c = mondayCalendar(calendar)
        return c.dateInterval(of: .weekOfYear, for: date)?.start ?? c.startOfDay(for: date)
    }

    static func weekKey(_ date: Date, calendar: Calendar = .current) -> String {
        ChallengeWire.dayKey(weekStart(date, calendar: calendar), calendar: calendar)
    }

    /// The Monday after the bet's week (exclusive end).
    static func weekEnd(_ key: String, calendar: Calendar = .current) -> Date? {
        ChallengeWire.date(fromKey: key, calendar: calendar).flatMap { calendar.date(byAdding: .day, value: 7, to: $0) }
    }

    static func isOver(_ bet: Bet, now: Date, calendar: Calendar = .current) -> Bool {
        guard let end = weekEnd(bet.week, calendar: calendar) else { return false }
        return now >= end
    }

    /// Days left in the bet's week, counting today.
    static func daysLeft(_ bet: Bet, now: Date, calendar: Calendar = .current) -> Int {
        guard let end = weekEnd(bet.week, calendar: calendar) else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0)
    }

    // MARK: - Scoring

    /// Who's ahead (or won). nil until both sides have a number.
    static func leader(_ metric: Metric, you: Double?, friend: Double?) -> Side? {
        guard let you, let friend else { return nil }
        if abs(you - friend) < 0.0001 { return .tie }
        return (you > friend) == metric.higherWins ? .you : .friend
    }

    /// A finished, accepted bet with both numbers in.
    static func winner(_ bet: Bet, now: Date, calendar: Calendar = .current) -> Side? {
        guard bet.status == .active, isOver(bet, now: now, calendar: calendar) else { return nil }
        return leader(bet.metric, you: bet.youScore, friend: bet.friendScore)
    }

    static func isSettled(_ bet: Bet, now: Date, calendar: Calendar = .current) -> Bool {
        winner(bet, now: now, calendar: calendar) != nil
    }

    /// "Loser buys wings 🍗" → "Dave buys wings 🍗"; anything else → "You owe Dave: …".
    static func owes(_ bet: Bet, winner: Side, friendName: String) -> String? {
        guard winner != .tie else { return nil }
        let loserIsYou = winner == .friend
        let stake = bet.stake.trimmingCharacters(in: .whitespacesAndNewlines)
        if stake.lowercased().hasPrefix("loser ") {
            let rest = String(stake.dropFirst(6))
            return loserIsYou ? "You \(youForm(rest))" : "\(friendName) \(rest)"
        }
        return loserIsYou ? "You owe \(friendName): \(stake)" : "\(friendName) owes you: \(stake)"
    }

    /// "buys wings" → "buy wings", "does 50 burpees" → "do 50 burpees".
    static func youForm(_ phrase: String) -> String {
        let words = phrase.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = words.first else { return phrase }
        let irregular = ["does": "do", "has": "have", "is": "are", "goes": "go"]
        var base = irregular[verb] ?? verb
        if irregular[verb] == nil {
            if verb.hasSuffix("ies") { base = String(verb.dropLast(3)) + "y" }
            else if verb.hasSuffix("ches") || verb.hasSuffix("shes") || verb.hasSuffix("sses") { base = String(verb.dropLast(2)) }
            else if verb.hasSuffix("s") && !verb.hasSuffix("ss") { base = String(verb.dropLast()) }
        }
        return ([base] + words.dropFirst()).joined(separator: " ")
    }

    struct Ledger: Equatable {
        /// Settled bets nobody has marked paid, newest first.
        var unpaid: [Bet]
        var wins: Int
        var losses: Int
        var ties: Int
    }

    static func ledger(_ bets: [Bet], now: Date, calendar: Calendar = .current) -> Ledger {
        var l = Ledger(unpaid: [], wins: 0, losses: 0, ties: 0)
        for b in bets.sorted(by: { $0.week > $1.week }) {
            guard let w = winner(b, now: now, calendar: calendar) else { continue }
            switch w {
            case .you:    l.wins += 1
            case .friend: l.losses += 1
            case .tie:    l.ties += 1
            }
            if w != .tie, !b.paid { l.unpaid.append(b) }
        }
        return l
    }

    /// This week's bet worth showing: proposed or running (declined and
    /// cancelled ones fall away).
    static func current(_ bets: [Bet], now: Date, calendar: Calendar = .current) -> Bet? {
        let key = weekKey(now, calendar: calendar)
        return bets.filter { $0.week == key && ($0.status == .proposed || $0.status == .active) }
            .max { $0.createdAt < $1.createdAt }
    }

    // MARK: - Server

    /// The server's bet, from the point of view of `role` ("owner"/"friend").
    struct Wire: Codable, Equatable {
        var id: String
        var week: String
        var metric: String
        var stake: String
        var proposer: String
        var status: String
        var ownerScore: Double?
        var friendScore: Double?
        var paid: Int?
        var createdAt: String?
    }

    static func bet(from w: Wire, role: String) -> Bet? {
        guard let metric = Metric(rawValue: w.metric), let status = Status(rawValue: w.status) else { return nil }
        let mine = role == "owner"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Bet(id: w.id, week: w.week, metric: metric, stake: w.stake,
                   proposer: w.proposer == role ? .you : .friend, status: status,
                   youScore: mine ? w.ownerScore : w.friendScore,
                   friendScore: mine ? w.friendScore : w.ownerScore,
                   paid: (w.paid ?? 0) != 0,
                   createdAt: w.createdAt.flatMap { iso.date(from: $0) } ?? Date(timeIntervalSince1970: 0))
    }

    // MARK: - What to tell you

    enum Event: Equatable {
        case proposed(Bet)
        case accepted(Bet)
        case declined(Bet)
        case settled(Bet, Side)
    }

    /// What changed between two looks at the bets. `announced` holds the
    /// ids of settled bets already told about.
    static func events(old: [Bet], new: [Bet], announced: Set<String>, now: Date,
                       calendar: Calendar = .current) -> [Event] {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Event] = []
        for b in new {
            let prior = before[b.id]
            if prior == nil, b.proposer == .friend, b.status == .proposed { out.append(.proposed(b)) }
            if let prior, prior.status == .proposed, b.proposer == .you {
                if b.status == .active { out.append(.accepted(b)) }
                if b.status == .declined { out.append(.declined(b)) }
            }
            if !announced.contains(b.id), let w = winner(b, now: now, calendar: calendar) { out.append(.settled(b, w)) }
        }
        return out
    }

    static func alert(_ event: Event, friendName: String) -> (title: String, body: String) {
        switch event {
        case .proposed(let b):
            return ("\(friendName) wants a side bet 🎲", "\(b.metric.title) this week. Stakes: \(b.stake). Accept?")
        case .accepted(let b):
            return ("Bet's on 🤝", "\(friendName) accepted: \(b.metric.title.lowercased()) this week. \(b.stake).")
        case .declined(let b):
            return ("\(friendName) passed", "No \(b.metric.title.lowercased()) bet this week. Try another?")
        case .settled(let b, let w):
            let score = "\(b.metric.number(b.youScore ?? 0)) vs \(b.metric.number(b.friendScore ?? 0))"
            switch w {
            case .you:    return ("You won the side bet 🏆", "\(score). " + (owes(b, winner: w, friendName: friendName) ?? ""))
            case .friend: return ("\(friendName) took the side bet", "\(score). " + (owes(b, winner: w, friendName: friendName) ?? ""))
            case .tie:    return ("Side bet: dead even", "\(score). Nobody owes anybody. Run it back?")
            }
        }
    }
}
