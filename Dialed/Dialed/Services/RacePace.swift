//
//  RacePace.swift
//  Dialed
//
//  "You need 1.3 lb/week to beat Dave by Nov 19 — you're on 1.6."
//  Projects your friend's finish from their weigh-ins, works out the pace
//  you need from your trend weight to finish ahead, and checks it two ways:
//  what the scale trend says, and what your food log says (maintenance +
//  exercise − eaten). Ends with the daily calories that would get you
//  there. Pure Foundation, tested.
//

import Foundation

enum RacePace {

    struct Inputs {
        var scoring: WeightChallenge.Scoring
        var yourStart: Double
        /// Trend weight now.
        var yourTrend: Double
        /// lbs/week lost by trend over the last couple of weeks (positive = losing).
        var yourTrendRate: Double?
        /// lbs/week implied by logged food: (maintenance + earned − eaten) × 7 / 3500.
        var yourFoodRate: Double?
        var friendStart: Double?
        var friendWeighIns: [(date: Date, pounds: Double)]
        var challengeStart: Date
        var end: Date
        var now: Date = Date()
    }

    enum Status: Equatable { case ahead, onTrack, behind, unknown }

    struct Result: Equatable {
        /// lbs/week you need from today to finish ahead.
        var needed: Double
        /// Best read of your current pace (trend, else food log).
        var current: Double?
        var trendRate: Double?
        var foodRate: Double?
        /// Your friend's projected finish, lbs lost.
        var friendProjectedLoss: Double?
        /// Your projected finish at the current pace, lbs lost.
        var yourProjectedLoss: Double?
        var status: Status
        var weeksLeft: Double
    }

    /// Daily maintenance estimate — the same rule the calorie target uses.
    static func maintenance(weight: Double) -> Double { weight * 15 }

    static func compute(_ i: Inputs, calendar: Calendar = .current) -> Result {
        let daysLeft = max(1, Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: i.now),
                                                              to: calendar.startOfDay(for: i.end)).day ?? 1))
        let weeksLeft = daysLeft / 7
        let lostSoFar = i.yourStart - i.yourTrend
        let friendLoss = friendProjection(i, calendar: calendar)

        // What you need to have lost at the end, in lbs, to finish ahead
        // (a small buffer so a tie doesn't count as a win).
        var neededTotal: Double?
        if let f = friendLoss {
            switch i.scoring {
            case .pounds:
                neededTotal = f.lbs + 0.5
            case .percent:
                neededTotal = (f.percent + 0.25) / 100 * i.yourStart
            }
        }
        let needed = neededTotal.map { max(0, ($0 - lostSoFar) / weeksLeft) } ?? 0
        let current = i.yourTrendRate ?? i.yourFoodRate
        let yourProjected = current.map { lostSoFar + $0 * weeksLeft }

        let status: Status
        if neededTotal == nil || current == nil {
            status = .unknown
        } else if let c = current, c >= needed * 1.2 + 0.2 {
            status = .ahead
        } else if let c = current, c >= needed {
            status = .onTrack
        } else {
            status = .behind
        }
        return Result(needed: needed, current: current, trendRate: i.yourTrendRate, foodRate: i.yourFoodRate,
                      friendProjectedLoss: friendLoss?.lbs, yourProjectedLoss: yourProjected,
                      status: status, weeksLeft: weeksLeft)
    }

    /// Daily calories that would hold `rate` lbs/week at `weight`, plus
    /// whatever exercise earns back. Never below 1,500.
    static func calories(for rate: Double, weight: Double) -> Double {
        let target = maintenance(weight: weight) - rate * 3_500 / 7
        return max(1_500, (target / 10).rounded() * 10)
    }

    /// Friend's loss at the end (lbs and %): a line through their weigh-ins
    /// when there are 3+, else their average pace since the start. Their
    /// rate is capped at 3 lb/week so one big drop can't project nonsense.
    static func friendProjection(_ i: Inputs, calendar: Calendar = .current) -> (lbs: Double, percent: Double)? {
        let points = i.friendWeighIns.sorted { $0.date < $1.date }
        guard let start = i.friendStart ?? points.first?.pounds, start > 0, let last = points.last else { return nil }
        let daysToEnd = max(0, Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: last.date),
                                                               to: calendar.startOfDay(for: i.end)).day ?? 0))
        var perDay: Double
        if points.count >= 3, let first = points.first {
            let xs = points.map { Double(calendar.dateComponents([.day], from: first.date, to: $0.date).day ?? 0) }
            let ys = points.map(\.pounds)
            let n = Double(points.count), mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
            let den = zip(xs, xs).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - mx) }
            perDay = den > 0 ? -zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / den : 0
        } else {
            let elapsed = max(1, Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: i.challengeStart),
                                                                to: calendar.startOfDay(for: last.date)).day ?? 1))
            perDay = (start - last.pounds) / elapsed
        }
        perDay = max(-3.0 / 7, min(3.0 / 7, perDay))
        let lbs = (start - last.pounds) + perDay * daysToEnd
        return (lbs, lbs / start * 100)
    }

    /// lbs/week by trend weight over the last `days` (positive = losing).
    static func trendRate(_ series: [WeightChallengeEngine.DailyWeight], now: Date = Date(), days: Int = 14,
                          calendar: Calendar = .current) -> Double? {
        let today = calendar.startOfDay(for: now)
        guard let since = calendar.date(byAdding: .day, value: -days, to: today),
              let last = series.last(where: { $0.day <= today }),
              let first = series.first(where: { $0.day >= since && $0.day < last.day }) else { return nil }
        let span = Double(calendar.dateComponents([.day], from: first.day, to: last.day).day ?? 0)
        guard span >= 5 else { return nil }
        return (first.trend - last.trend) / span * 7
    }

    /// lbs/week implied by the food log over days you logged.
    static func foodRate(days: [(eaten: Double, earned: Double)], weight: Double) -> Double? {
        let logged = days.filter { $0.eaten > 300 }
        guard logged.count >= 3 else { return nil }
        let deficit = logged.reduce(0) { $0 + maintenance(weight: weight) + $1.earned - $1.eaten } / Double(logged.count)
        return deficit * 7 / 3_500
    }
}
