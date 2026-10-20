//
//  WeeklyHeadToHeadReport.swift
//  Dialed
//
//  The Sunday summary of your week against your friend: who took the
//  week on weight (in the challenge's scoring unit, trend vs trend so a
//  salty Saturday doesn't decide it), then steps, miles, workouts, PRs
//  and quest XP side by side, the side bet's result ("Dave buys wings
//  🍗"), where the race stands, and one nudge for next week. Pure
//  Foundation, tested; WeeklyReportService gathers the numbers.
//

import Foundation

enum WeeklyHeadToHeadReport {

    /// One side's week. Anything unknown stays nil and its row says so.
    struct SideWeek: Equatable {
        /// Trend weight going into the week and at its last weigh-in.
        var startTrend: Double?
        var endTrend: Double?
        var steps: Double?
        var miles: Double?
        var workouts: Double?
        var prs: Double?
        var xp: Double?

        /// lbs lost this week (negative = gained).
        var lost: Double? {
            guard let startTrend, let endTrend else { return nil }
            return startTrend - endTrend
        }
    }

    struct Inputs {
        var weekStart: Date
        var challengeStart: Date
        var scoring: WeightChallenge.Scoring
        var friendName: String
        var you: SideWeek
        var friend: SideWeek
        /// Starting weights, for % scoring.
        var yourStartWeight: Double?
        var friendStartWeight: Double?
        var bet: SideBets.Bet?
        var raceStatus: RacePace.Status?
        /// lbs/week needed from here to finish ahead.
        var neededRate: Double?
        var leader: WeightChallengeEngine.Leader = .unknown
        /// Overall lead in the scoring unit.
        var margin: Double = 0
    }

    struct Row: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var symbol: String
        var you: String
        var friend: String?
        /// "you", "friend" or "tie"; nil when only one side has a number.
        var winner: String?
    }

    struct Report: Codable, Equatable {
        /// Monday "yyyy-MM-dd".
        var week: String
        var weekNumber: Int
        var friendName: String
        var headline: String
        var subline: String
        var rows: [Row]
        var betLine: String?
        var standing: String?
        var nudge: String
        /// Who took the week on weight; nil when it can't be told.
        var weekWinner: String?
    }

    // MARK: - Pieces

    /// Week 1 starts with the challenge (the Monday of its first week).
    static func weekNumber(challengeStart: Date, weekStart: Date, calendar: Calendar = .current) -> Int {
        let first = SideBets.weekStart(challengeStart, calendar: calendar)
        let days = calendar.dateComponents([.day], from: first, to: SideBets.weekStart(weekStart, calendar: calendar)).day ?? 0
        return max(1, days / 7 + 1)
    }

    /// Trend weight before the week (the last day before Monday, else its
    /// first weigh-in) and at the week's last weigh-in.
    static func weekTrend(_ readings: [WeightReading], weekStart: Date,
                          calendar: Calendar = .current) -> (start: Double?, end: Double?) {
        let start = SideBets.weekStart(weekStart, calendar: calendar)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return (nil, nil) }
        let series = WeightChallengeEngine.dailySeries(readings, calendar: calendar)
        let inWeek = series.filter { $0.day >= start && $0.day < end }
        guard let last = inWeek.last else { return (nil, nil) }
        let before = series.last { $0.day < start } ?? inWeek.first
        guard let before, before.day != last.day else { return (nil, nil) }
        return (before.trend, last.trend)
    }

    /// Change in the scoring unit (positive = lost).
    static func scored(_ lost: Double?, startWeight: Double?, scoring: WeightChallenge.Scoring) -> Double? {
        guard let lost else { return nil }
        switch scoring {
        case .pounds:  return lost
        case .percent:
            guard let w = startWeight, w > 0 else { return nil }
            return lost / w * 100
        }
    }

    static func format(_ value: Double, _ scoring: WeightChallenge.Scoring) -> String {
        scoring == .percent ? String(format: "%.1f%%", value) : String(format: "%.1f lb", value)
    }

    /// "−1.2 lb" lost / "+0.4 lb" gained.
    static func formatChange(_ value: Double, _ scoring: WeightChallenge.Scoring) -> String {
        (value >= 0 ? "−" : "+") + format(abs(value), scoring)
    }

    private static func winner(_ you: Double?, _ friend: Double?, higherWins: Bool = true, tolerance: Double = 0.0001) -> String? {
        guard let you, let friend else { return nil }
        if abs(you - friend) <= tolerance { return "tie" }
        return (you > friend) == higherWins ? "you" : "friend"
    }

    // MARK: - Build

    static func build(_ i: Inputs, calendar: Calendar = .current) -> Report {
        let n = weekNumber(challengeStart: i.challengeStart, weekStart: i.weekStart, calendar: calendar)
        let name = i.friendName
        let youScore = scored(i.you.lost, startWeight: i.yourStartWeight, scoring: i.scoring)
        let friendScore = scored(i.friend.lost, startWeight: i.friendStartWeight, scoring: i.scoring)
        let tolerance = i.scoring == .percent ? 0.05 : 0.1
        let weekWinner = winner(youScore, friendScore, tolerance: tolerance)

        var rows: [Row] = []
        if youScore != nil || friendScore != nil {
            rows.append(Row(id: "weight", title: "Weight", symbol: "scalemass.fill",
                            you: youScore.map { formatChange($0, i.scoring) } ?? "—",
                            friend: friendScore.map { formatChange($0, i.scoring) },
                            winner: weekWinner))
        }
        func add(_ id: String, _ title: String, _ symbol: String, _ you: Double?, _ friend: Double?,
                 _ fmt: (Double) -> String) {
            guard you != nil || friend != nil else { return }
            rows.append(Row(id: id, title: title, symbol: symbol,
                            you: you.map(fmt) ?? "—", friend: friend.map(fmt), winner: winner(you, friend)))
        }
        add("steps", "Steps", "shoeprints.fill", i.you.steps, i.friend.steps) { Int($0.rounded()).formatted() }
        add("miles", "Miles", "figure.walk", i.you.miles, i.friend.miles) { String(format: "%.1f", $0) }
        add("workouts", "Workouts", "dumbbell.fill", i.you.workouts, i.friend.workouts) { "\(Int($0.rounded()))" }
        add("prs", "PRs", "trophy.fill", i.you.prs, i.friend.prs) { "\(Int($0.rounded()))" }
        add("xp", "Quest XP", "star.fill", i.you.xp, i.friend.xp) { "\(Int($0.rounded()))" }

        // Headline: the week is decided on weight, like the race.
        let headline: String
        switch (weekWinner, youScore, friendScore) {
        case (.some("you"), let y?, let f?):    headline = "You took week \(n) by \(format(y - f, i.scoring))"
        case (.some("friend"), let y?, let f?): headline = "\(name) took week \(n) by \(format(f - y, i.scoring))"
        case (.some("tie"), _, _):              headline = "Week \(n) was a dead heat"
        case (_, let y?, nil):
            headline = y >= 0 ? "Week \(n): you're down \(format(y, i.scoring))" : "Week \(n): you're up \(format(-y, i.scoring))"
        default:                         headline = "Week \(n) in the books"
        }

        let decided = rows.filter { $0.winner == "you" || $0.winner == "friend" }
        let won = decided.filter { $0.winner == "you" }.count
        let subline = decided.isEmpty
            ? "Once \(name)'s numbers come in, every category gets a winner."
            : "You won \(won) of \(decided.count) categor\(decided.count == 1 ? "y" : "ies") this week."

        // Side bet: settled (or where it stands on Sunday night).
        var betLine: String?
        if let bet = i.bet, bet.status == .active {
            if let side = SideBets.leader(bet.metric, you: bet.youScore, friend: bet.friendScore) {
                if side == .tie {
                    betLine = "Side bet (\(bet.metric.title.lowercased())) tied. Nobody owes anything."
                } else {
                    betLine = SideBets.owes(bet, winner: side, friendName: name)
                }
            } else {
                betLine = "Side bet: \(bet.metric.title.lowercased()), waiting on \(name)'s number."
            }
        }

        var standing: String?
        switch i.leader {
        case .you:     standing = "Overall you lead by \(format(i.margin, i.scoring))."
        case .friend:  standing = "Overall \(name) leads by \(format(i.margin, i.scoring))."
        case .tied:    standing = "Overall it's dead even."
        case .unknown: standing = nil
        }

        var nudge: String
        switch i.raceStatus {
        case .behind?:
            nudge = i.neededRate.map { "You need \(String(format: "%.1f", $0)) lb a week from here. Tighten one weekend meal and add two walks." }
                ?? "Tighten one weekend meal and add two walks next week."
        case .onTrack?: nudge = "Right on pace. Same plan, plus one extra walk to build a buffer."
        case .ahead?:   nudge = "Ahead of pace. Repeat this week and the race is yours."
        default:        nudge = "Weigh in every morning next week so the race has a clear read."
        }
        if let lostRow = rows.first(where: { $0.winner == "friend" && $0.id != "weight" }) {
            switch lostRow.id {
            case "steps", "miles": nudge += " \(name) out-walked you, so a 20-minute walk 3 days closes it."
            case "workouts":       nudge += " \(name) trained more, so lock in your sessions on the calendar."
            default: break
            }
        }

        return Report(week: ChallengeWire.dayKey(SideBets.weekStart(i.weekStart, calendar: calendar), calendar: calendar),
                      weekNumber: n, friendName: name, headline: headline, subline: subline, rows: rows,
                      betLine: betLine, standing: standing, nudge: nudge, weekWinner: weekWinner)
    }

    /// Plain text for Messages when the challenge server can't take it.
    static func text(_ r: Report) -> String {
        var lines = ["📊 \(r.headline)"]
        for row in r.rows {
            let mark = row.winner == "you" ? " ✅" : ""
            lines.append("• \(row.title): me \(row.you)\(row.friend.map { " · \(r.friendName) \($0)" } ?? "")\(mark)")
        }
        if let b = r.betLine { lines.append("🎲 \(b)") }
        if let s = r.standing { lines.append(s) }
        lines.append("— sent from Dialed")
        return lines.joined(separator: "\n")
    }
}
