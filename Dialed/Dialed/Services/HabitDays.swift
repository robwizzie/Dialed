//
//  HabitDays.swift
//  Dialed
//
//  One shared verdict per day — did you get your mile, hit protein, log
//  your food, train, drink your water, weigh in, stay in budget — that
//  quests, badges and the habit heatmap all read, so a "done" day is the
//  same everywhere. Streak math lives here too. Pure Foundation, tested;
//  HabitDaysLoader builds the days.
//

import Foundation

enum HabitDays {

    /// The habits the heatmap tracks (water, weigh-in and budget feed
    /// quests and badges but don't get a row).
    enum Habit: String, CaseIterable, Identifiable {
        case mile, protein, logging, workout
        var id: String { rawValue }

        var title: String {
            switch self {
            case .mile:    return "Mile"
            case .protein: return "Protein"
            case .logging: return "Logging"
            case .workout: return "Workout"
            }
        }

        var symbol: String {
            switch self {
            case .mile:    return "figure.walk"
            case .protein: return "bolt.heart.fill"
            case .logging: return "fork.knife"
            case .workout: return "dumbbell.fill"
            }
        }
    }

    struct Day: Equatable, Identifiable {
        var date: Date
        var miles: Double = 0
        var protein: Double = 0
        var calories: Double = 0
        var foodEntries = 0
        var waterOz: Double = 0
        var workout = false
        var weighedIn = false
        /// Earliest weigh-in time that day.
        var weighInTime: Date?
        /// Targets in effect that day.
        var mileGoal: Double = 1
        var proteinTarget: Double = 150
        var waterTarget: Double = 100
        var calorieBudget: Double = 2_200

        var id: Date { date }

        var mileDone: Bool { miles >= mileGoal - 0.005 }
        var proteinHit: Bool { proteinTarget > 0 && protein >= proteinTarget }
        /// Two or more foods, or a real day's worth of calories.
        var logged: Bool { foodEntries >= 2 || calories >= 800 }
        var waterHit: Bool { waterTarget > 0 && waterOz >= waterTarget }
        /// Logged and not over budget (an unlogged day isn't "in budget").
        var inBudget: Bool { logged && calories <= calorieBudget }

        func did(_ habit: Habit) -> Bool {
            switch habit {
            case .mile:    return mileDone
            case .protein: return proteinHit
            case .logging: return logged
            case .workout: return workout
            }
        }

        /// 0…4: how many heatmap habits you hit.
        var score: Int { Habit.allCases.filter(did).count }
        /// Every habit, water and budget too.
        var perfect: Bool { score == Habit.allCases.count && waterHit && inBudget }
    }

    // MARK: - Streaks

    struct Streak: Equatable {
        var current: Int
        var best: Int
    }

    /// Consecutive days meeting `test`, ending today — or yesterday, since
    /// today isn't over yet — plus the best run in `days`.
    static func streak(_ days: [Day], today: Date, calendar: Calendar = .current, _ test: (Day) -> Bool) -> Streak {
        var byDay: [Date: Day] = [:]
        for d in days { byDay[calendar.startOfDay(for: d.date)] = d }

        var best = 0, run = 0
        var previous: Date?
        for day in byDay.keys.sorted() {
            let consecutive = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day
            if let d = byDay[day], test(d) {
                run = consecutive ? run + 1 : 1
            } else {
                run = 0
            }
            best = max(best, run)
            previous = day
        }

        let start = calendar.startOfDay(for: today)
        var cursor = byDay[start].map(test) == true ? start : (calendar.date(byAdding: .day, value: -1, to: start) ?? start)
        var current = 0
        while let d = byDay[cursor], test(d) {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return Streak(current: current, best: max(best, current))
    }

    static func streak(_ days: [Day], habit: Habit, today: Date, calendar: Calendar = .current) -> Streak {
        streak(days, today: today, calendar: calendar) { $0.did(habit) }
    }

    /// The most days in any 7-day window meeting `test`.
    static func bestWeek(_ days: [Day], calendar: Calendar = .current, _ test: (Day) -> Bool) -> Int {
        let hits = Set(days.filter(test).map { calendar.startOfDay(for: $0.date) })
        var best = 0
        for start in hits {
            let window = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            best = max(best, window.filter(hits.contains).count)
        }
        return best
    }
}
