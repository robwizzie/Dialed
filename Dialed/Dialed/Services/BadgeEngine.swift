//
//  BadgeEngine.swift
//  Dialed
//
//  The trophy wall: first 5 lb down, a 30-day mile streak, the PR club, a
//  perfect week of logging… Each badge reads the shared habit days plus a
//  few totals and reports how close you are, so locked ones show a
//  progress ring. Pure Foundation, tested; unlock dates are kept by
//  GameStore.
//

import Foundation

enum BadgeEngine {

    enum Tier: Int, Comparable {
        case bronze, silver, gold
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    struct Badge: Equatable, Identifiable {
        var id: String
        var title: String
        /// "Lose 5 lb by trend weight"
        var detail: String
        var symbol: String
        var tier: Tier
    }

    struct Status: Equatable, Identifiable {
        var badge: Badge
        var current: Double
        var target: Double
        var unit: String
        var id: String { badge.id }
        var unlocked: Bool { current >= target }
        var progress: Double { target > 0 ? min(1, max(0, current / target)) : 0 }
        /// "3 of 7 days"
        var progressText: String {
            let c = current.rounded(.down) == current ? "\(Int(current))" : String(format: "%.1f", current)
            return "\(c) of \(Int(target)) \(unit)"
        }
    }

    /// Everything the badges look at.
    struct Inputs {
        var days: [HabitDays.Day]
        var today: Date
        /// lbs lost by trend weight (from the challenge start, else your
        /// heaviest recent trend).
        var lostByTrend: Double = 0
        /// Longest mile streak ever (MileHistory knows more than `days`).
        var bestMileStreak: Int = 0
        var totalMiles: Double = 0
        var prCount: Int = 0
        var funActivities: Int = 0
        /// Longest run of days ahead of your friend.
        var daysLeading: Int = 0
        var level: Int = 1
        /// Days you finished all three quests.
        var questSweeps: Int = 0
    }

    static func evaluate(_ i: Inputs, calendar: Calendar = .current) -> [Status] {
        func best(_ test: (HabitDays.Day) -> Bool) -> Double {
            Double(HabitDays.streak(i.days, today: i.today, calendar: calendar, test).best)
        }
        let logging = best { $0.logged }
        let weighIns = best { $0.weighedIn }
        let protein = best { $0.proteinHit }
        let water = best { $0.waterHit }
        let perfect = Double(i.days.filter(\.perfect).count)
        let workoutWeek = Double(HabitDays.bestWeek(i.days, calendar: calendar) { $0.workout })
        let mileStreak = Double(max(i.bestMileStreak, HabitDays.streak(i.days, habit: .mile, today: i.today, calendar: calendar).best))

        func s(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ tier: Tier,
               _ current: Double, _ target: Double, _ unit: String) -> Status {
            Status(badge: Badge(id: id, title: title, detail: detail, symbol: symbol, tier: tier),
                   current: current, target: target, unit: unit)
        }
        return [
            s("down5", "First 5", "Lose 5 lb by trend weight", "arrow.down.circle.fill", .bronze, i.lostByTrend, 5, "lb"),
            s("down10", "Double Digits", "Lose 10 lb by trend weight", "arrow.down.circle.fill", .silver, i.lostByTrend, 10, "lb"),
            s("down15", "Fifteen Gone", "Lose 15 lb by trend weight", "arrow.down.circle.fill", .gold, i.lostByTrend, 15, "lb"),
            s("down20", "Twenty Club", "Lose 20 lb by trend weight", "crown.fill", .gold, i.lostByTrend, 20, "lb"),
            s("mile7", "Week of Miles", "A mile a day, 7 days straight", "figure.walk", .bronze, mileStreak, 7, "days"),
            s("mile14", "Fortnight Feet", "A mile a day, 14 days straight", "figure.walk.motion", .silver, mileStreak, 14, "days"),
            s("mile30", "Mile Monk", "A mile a day, 30 days straight", "figure.walk.diamond.fill", .gold, mileStreak, 30, "days"),
            s("miles100", "Century", "100 miles walked or run", "road.lanes", .silver, i.totalMiles, 100, "mi"),
            s("pr1", "First PR", "Set a personal record", "trophy.fill", .bronze, Double(i.prCount), 1, "PRs"),
            s("pr10", "PR Club", "Set 10 personal records", "trophy.circle.fill", .gold, Double(i.prCount), 10, "PRs"),
            s("log7", "Perfect Week", "Log your food 7 days in a row", "checklist.checked", .bronze, logging, 7, "days"),
            s("log30", "Food Journalist", "Log your food 30 days in a row", "book.closed.fill", .gold, logging, 30, "days"),
            s("weigh7", "Early Bird", "Weigh in 7 days in a row", "scalemass.fill", .bronze, weighIns, 7, "days"),
            s("protein7", "Protein Pro", "Hit protein 7 days in a row", "bolt.heart.fill", .silver, protein, 7, "days"),
            s("water7", "Hydrated", "Hit your water 7 days in a row", "drop.fill", .bronze, water, 7, "days"),
            s("workout4", "Four-a-Week", "Train 4 times in 7 days", "dumbbell.fill", .silver, workoutWeek, 4, "workouts"),
            s("perfect1", "Perfect Day", "Every habit, water and budget in one day", "star.fill", .silver, perfect, 1, "days"),
            s("fun1", "Play Counts", "Name your first active moment", "figure.pickleball", .bronze, Double(i.funActivities), 1, "activities"),
            s("lead7", "Front-runner", "Lead your friend for 7 days straight", "flag.checkered", .gold, Double(i.daysLeading), 7, "days"),
            s("sweep3", "Triple Threat", "Finish all three quests on 3 days", "target", .silver, Double(i.questSweeps), 3, "days"),
            s("level5", "Locked In", "Reach level 5", "lock.circle.fill", .silver, Double(i.level), 5, "level"),
            s("level12", "Elite", "Reach level 12", "seal.fill", .gold, Double(i.level), 12, "level")
        ]
    }

    /// Every badge, for looking one up by id.
    static var catalog: [Badge] { evaluate(Inputs(days: [], today: Date())).map(\.badge) }

    // MARK: - Leading your friend

    /// Longest run of days you were ahead, comparing each day's latest
    /// known weights from both sides (in the challenge's scoring).
    static func longestLead(yours: [(day: Date, pounds: Double)], yourStart: Double,
                            friend: [(day: Date, pounds: Double)], friendStart: Double,
                            percent: Bool, from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        guard yourStart > 0, friendStart > 0 else { return 0 }
        let mine = yours.sorted { $0.day < $1.day }, theirs = friend.sorted { $0.day < $1.day }
        var best = 0, run = 0
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            if let y = mine.last(where: { $0.day <= day }), let f = theirs.last(where: { $0.day <= day }) {
                let you = percent ? (yourStart - y.pounds) / yourStart : yourStart - y.pounds
                let them = percent ? (friendStart - f.pounds) / friendStart : friendStart - f.pounds
                run = you > them ? run + 1 : 0
                best = max(best, run)
            } else {
                run = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return best
    }
}
