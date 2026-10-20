//
//  WrappedBuilder.swift
//  Dialed
//
//  Dialed Wrapped: your challenge as a stack of story cards — pounds lost,
//  miles walked, weight lifted, PRs, your best week, your most consistent
//  habit, the moment you passed your friend, a fun stat, and the final
//  head-to-head. Works mid-challenge too ("so far"). Every card is built
//  from numbers the app already has; cards without enough data are left
//  out. Pure Foundation, tested.
//

import Foundation

enum WrappedBuilder {

    struct Inputs {
        var friendName: String
        var start: Date
        var end: Date
        var now: Date = Date()
        var scoring: WeightChallenge.Scoring = .pounds
        /// Your daily weights (any range; the challenge window is picked out).
        var series: [WeightChallengeEngine.DailyWeight]
        var startWeightOverride: Double?
        var friendStart: Double?
        var friendWeighIns: [(date: Date, pounds: Double)] = []
        var milesByDay: [Date: Double] = [:]
        var mileGoal: Double = 1
        /// Completed sets, including ones from before the challenge (history for PRs).
        var sets: [StrengthMilestones.SetRecord] = []
        var workoutDays: Set<Date> = []
        var foodLoggedDays: Set<Date> = []
        var funActivities: [(name: String, date: Date, minutes: Double)] = []
    }

    struct Card: Identifiable, Equatable {
        enum Kind: String { case intro, lost, miles, lifting, prs, bestWeek, habit, passed, fun, final }

        let kind: Kind
        /// Small caps line above the number.
        let eyebrow: String
        /// The big number ("−8.4"), or a short phrase.
        let value: String
        let unit: String
        let title: String
        let detail: [String]

        var id: String { kind.rawValue }

        /// One line for sharing.
        var shareText: String {
            ([eyebrow, "\(value)\(unit.isEmpty ? "" : " \(unit)") · \(title)"] + detail).joined(separator: "\n")
        }
    }

    static func isFinished(_ i: Inputs, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: i.now) >= calendar.startOfDay(for: i.end)
    }

    static func build(_ i: Inputs, calendar: Calendar = .current) -> [Card] {
        let start = calendar.startOfDay(for: i.start)
        let last = min(calendar.startOfDay(for: i.now), calendar.startOfDay(for: i.end))
        let finished = isFinished(i, calendar: calendar)
        let daysIn = max(1, (calendar.dateComponents([.day], from: start, to: last).day ?? 0) + 1)
        let totalDays = max(1, calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: i.end)).day ?? 1)
        let window = i.series.filter { $0.day >= start && $0.day <= last }
        let inWindow = { (d: Date) in d >= start && d <= last }
        var cards: [Card] = []

        // Intro
        cards.append(Card(kind: .intro, eyebrow: finished ? "DIALED WRAPPED" : "DIALED WRAPPED · SO FAR",
                          value: "\(min(daysIn, totalDays))", unit: "days",
                          title: "You vs \(i.friendName)",
                          detail: [finished ? "The challenge is done. Here's how it went." : "Day \(min(daysIn, totalDays)) of \(totalDays). Here's the story so far."]))

        // Pounds lost
        let startWeight = i.startWeightOverride ?? window.first?.pounds ?? i.series.last(where: { $0.day < start })?.pounds
        if let s = startWeight, let first = window.first, let now = window.last {
            let trendLost = first.trend - now.trend
            let scaleLost = s - now.pounds
            cards.append(Card(kind: .lost, eyebrow: "POUNDS DOWN", value: signed(-scaleLost), unit: "lb",
                              title: scaleLost > 0 ? "Gone. For real." : "Holding the line",
                              detail: ["Scale \(one(s)) → \(one(now.pounds))",
                                       "Trend \(one(first.trend)) → \(one(now.trend)) (\(signed(-trendLost)) lb)"]))
        }

        // Miles
        let miles = i.milesByDay.filter { inWindow($0.key) }
        let totalMiles = miles.values.reduce(0, +)
        if totalMiles > 0 {
            let done = miles.values.filter { $0 >= i.mileGoal - 0.0001 }.count
            cards.append(Card(kind: .miles, eyebrow: "MILES ON FOOT", value: one(totalMiles), unit: "mi",
                              title: "\(done) mile days out of \(daysIn)",
                              detail: ["Longest streak: \(longestStreak(miles.filter { $0.value >= i.mileGoal - 0.0001 }.map(\.key), calendar: calendar)) days"]))
        }

        // Lifting
        let challengeSets = i.sets.filter { inWindow(calendar.startOfDay(for: $0.date)) }
        let workouts = i.workoutDays.filter(inWindow).count
        if workouts > 0 || !challengeSets.isEmpty {
            let volume = challengeSets.reduce(0) { $0 + $1.weight * Double($1.reps) }
            var detail = ["\(challengeSets.count) sets finished"]
            let cars = Int((volume / 4_000).rounded())
            if cars >= 1 { detail.append(cars == 1 ? "About a whole car's worth of weight" : "That's about \(cars) cars' worth of weight") }
            cards.append(Card(kind: .lifting, eyebrow: "WEIGHT MOVED", value: thousands(volume), unit: "lb",
                              title: "\(max(workouts, Set(challengeSets.map { calendar.startOfDay(for: $0.date) }).count)) workouts",
                              detail: detail))
        }

        // PRs, session by session against everything before it.
        let sessionDays = Set(challengeSets.map { calendar.startOfDay(for: $0.date) }).sorted()
        var prs: [StrengthMilestones.PR] = []
        for day in sessionDays {
            let session = challengeSets.filter { calendar.startOfDay(for: $0.date) == day }
            let history = i.sets.filter { calendar.startOfDay(for: $0.date) < day }
            prs += StrengthMilestones.prs(session: session, history: history)
        }
        if !prs.isEmpty {
            let best = StrengthMilestones.bests(challengeSets).values.max { $0.e1RM < $1.e1RM }
            var detail = prs.suffix(3).map(\.text)
            if let best { detail.append("Strongest lift: \(best.exercise), est. max \(Int(best.e1RM.rounded())) lb") }
            cards.append(Card(kind: .prs, eyebrow: "PERSONAL RECORDS", value: "\(prs.count)", unit: prs.count == 1 ? "PR" : "PRs",
                              title: "Stronger than you started", detail: detail))
        }

        // Best week: the biggest seven-day drop in trend weight.
        var bestWeek: (start: Date, drop: Double)?
        for d in window {
            guard let weekLater = calendar.date(byAdding: .day, value: 7, to: d.day),
                  let after = window.last(where: { $0.day <= weekLater && $0.day > d.day }),
                  (calendar.dateComponents([.day], from: d.day, to: after.day).day ?? 0) >= 5 else { continue }
            let drop = d.trend - after.trend
            if drop > (bestWeek?.drop ?? 0.2) { bestWeek = (d.day, drop) }
        }
        if let w = bestWeek {
            cards.append(Card(kind: .bestWeek, eyebrow: "BEST WEEK", value: signed(-w.drop), unit: "lb",
                              title: "Week of \(w.start.formatted(.dateTime.month(.abbreviated).day()))",
                              detail: ["Your trend weight's biggest seven-day drop."]))
        }

        // Most consistent habit
        let weighInDays = Set(window.map(\.day))
        let habits: [(String, Int)] = [
            ("walked your mile", miles.values.filter { $0 >= i.mileGoal - 0.0001 }.count),
            ("logged your food", i.foodLoggedDays.filter(inWindow).count),
            ("weighed in", weighInDays.count),
            ("trained", workouts)
        ]
        if let top = habits.max(by: { $0.1 < $1.1 }), top.1 >= 3 {
            let pct = Int((Double(top.1) / Double(daysIn) * 100).rounded())
            cards.append(Card(kind: .habit, eyebrow: "MOST CONSISTENT", value: "\(min(100, pct))", unit: "%",
                              title: "You \(top.0) \(top.1) of \(daysIn) days",
                              detail: habits.filter { $0.0 != top.0 && $0.1 > 0 }.map { "\($0.1) days \($0.0)" }))
        }

        // The moment you passed your friend
        let friendPoints = i.friendWeighIns.sorted { $0.date < $1.date }
        let friendStart = i.friendStart ?? friendPoints.first?.pounds
        if let s = startWeight, let fs = friendStart, fs > 0, !friendPoints.isEmpty, !window.isEmpty {
            func yourLoss(_ d: WeightChallengeEngine.DailyWeight) -> Double {
                i.scoring == .percent ? (s - d.pounds) / s * 100 : s - d.pounds
            }
            func friendLoss(on day: Date) -> Double {
                guard let p = friendPoints.last(where: { calendar.startOfDay(for: $0.date) <= day }) else { return 0 }
                return i.scoring == .percent ? (fs - p.pounds) / fs * 100 : fs - p.pounds
            }
            var wasBehind = false
            var passed: Date?
            for d in window {
                let you = yourLoss(d), them = friendLoss(on: d.day)
                if you < them { wasBehind = true }
                if wasBehind, you > them { passed = d.day; break }
            }
            if let passed {
                cards.append(Card(kind: .passed, eyebrow: "THE MOMENT", value: passed.formatted(.dateTime.month(.abbreviated).day()), unit: "",
                                  title: "You passed \(i.friendName)",
                                  detail: ["Day \((calendar.dateComponents([.day], from: start, to: passed).day ?? 0) + 1). You'd been chasing. Then you weren't."]))
            } else if !wasBehind, window.count >= 3 {
                cards.append(Card(kind: .passed, eyebrow: "THE MOMENT", value: "Day 1", unit: "",
                                  title: "You led from the start",
                                  detail: ["\(i.friendName) never got in front."]))
            }
        }

        // Fun stat
        let fun = i.funActivities.filter { inWindow(calendar.startOfDay(for: $0.date)) }
        if !fun.isEmpty {
            let byName = Dictionary(grouping: fun, by: \.name)
            if let top = byName.max(by: { $0.value.count < $1.value.count }) {
                let minutes = Int(top.value.reduce(0) { $0 + $1.minutes })
                cards.append(Card(kind: .fun, eyebrow: "ACTIVE MOMENTS", value: "\(top.value.count)×", unit: "",
                                  title: top.key,
                                  detail: ["\(minutes) minutes of it", "\(fun.count) active moments in all"]))
            }
        }

        // Final head-to-head
        if let s = startWeight, let now = window.last {
            let unit = i.scoring == .percent ? "%" : "lb"
            let you = i.scoring == .percent ? (s - now.pounds) / s * 100 : s - now.pounds
            var detail = ["You: \(signed(-you)) \(unit)"]
            var title = finished ? "Final" : "Right now"
            if let fs = friendStart, fs > 0, let p = friendPoints.last {
                let them = i.scoring == .percent ? (fs - p.pounds) / fs * 100 : fs - p.pounds
                detail.append("\(i.friendName): \(signed(-them)) \(unit)")
                let gap = abs(you - them)
                if gap < (i.scoring == .percent ? 0.05 : 0.1) {
                    title += ": dead even"
                } else {
                    title += you > them ? ": you \(finished ? "win" : "lead")" : ": \(i.friendName) \(finished ? "wins" : "leads")"
                    detail.append("By \(one(gap)) \(unit)")
                }
            }
            cards.append(Card(kind: .final, eyebrow: "YOU VS \(i.friendName.uppercased())", value: signed(-you), unit: unit,
                              title: title, detail: detail))
        }
        return cards
    }

    // MARK: - Helpers

    static func longestStreak(_ days: [Date], calendar: Calendar = .current) -> Int {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for d in sorted {
            if let p = previous, calendar.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = d
        }
        return best
    }

    static func one(_ v: Double) -> String { String(format: "%.1f", v) }

    /// −8.4 / +1.2
    static func signed(_ v: Double) -> String { (v <= 0 ? "−" : "+") + String(format: "%.1f", abs(v)) }

    static func thousands(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }
}
