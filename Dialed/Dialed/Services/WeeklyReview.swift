//
//  WeeklyReview.swift
//  Dialed
//
//  The math behind the Sunday weekly review: which seven days, averages
//  against your targets, days on target, best and worst day, the weight
//  trend across the week, and the one thing to fix next week.
//
//  Day score: the same 0–100 score Home's avatar mood uses
//  (AvatarMood.read — water 20, steps 20, protein 20, calorie budget 15,
//  sleep 15, weigh-in 10), judged at 9 PM so pace = 100% of every target.
//  Days with nothing logged at all are left out of best / worst.
//
//  Pure Foundation, unit-tested.
//

import Foundation

enum WeeklyReview {

    /// What one day looked like. nil = no data that day.
    struct Day: Equatable {
        var date: Date
        var caloriesIn: Double?
        var proteinGrams: Double?
        var waterOz: Double?
        var steps: Int?
        var sleepHours: Double?
        var weighedIn = false
        var workoutDone = false

        var hasData: Bool {
            (caloriesIn ?? 0) > 0 || (proteinGrams ?? 0) > 0 || (waterOz ?? 0) > 0
                || (steps ?? 0) > 0 || sleepHours != nil || weighedIn
        }
    }

    struct Targets: Equatable {
        var calories: Double
        var protein: Double
        var waterOz: Double
        var steps: Int = 10_000
        var sleepHours: Double = 7
    }

    struct DayScore: Equatable {
        let date: Date
        let score: Int
    }

    struct Summary: Equatable {
        let start: Date
        let end: Date
        let days: [Day]
        let scores: [DayScore]

        let weightStart: Double?
        let weightEnd: Double?
        /// Trend change across the week, lbs (negative = loss).
        let weightChange: Double?
        /// lbs / week at that pace (negative = losing).
        let weeklyRate: Double?

        let avgCalories: Double?
        let avgProtein: Double?
        let avgWater: Double?
        let avgSteps: Double?
        let avgSleep: Double?

        let calorieDays: Int
        let proteinDays: Int
        let waterDays: Int
        let stepDays: Int
        let sleepDays: Int
        let weighInDays: Int
        let workoutsDone: Int
        /// Days with any food logged.
        let foodLoggedDays: Int

        var best: DayScore? { scores.max { $0.score < $1.score } }
        /// Worst day, or nil when it's the same as the best.
        var worst: DayScore? {
            guard scores.count >= 2 else { return nil }
            return scores.min { $0.score < $1.score }
        }
        var averageScore: Int? {
            scores.isEmpty ? nil : Int((Double(scores.map(\.score).reduce(0, +)) / Double(scores.count)).rounded())
        }
    }

    // MARK: - Which week

    /// The week to review: Monday → Sunday. On a Sunday that's this week
    /// (ending today); any other day it's the last finished week. Each
    /// `weeksBack` steps one more week into the past.
    static func weekRange(now: Date, weeksBack: Int = 0, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)   // 1 = Sunday
        let backToSunday = (weekday + 6) % 7                         // Sun 0, Mon 1 … Sat 6
        let sunday = calendar.date(byAdding: .day, value: -backToSunday - 7 * max(0, weeksBack), to: today) ?? today
        let monday = calendar.date(byAdding: .day, value: -6, to: sunday) ?? sunday
        return (monday, sunday)
    }

    static func days(from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var d = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while d <= last {
            out.append(d)
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    /// "yyyy-MM-dd" keys from UserDefaults `workout.doneDays`.
    static func workoutKeys(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Scoring

    static func score(_ day: Day, targets: Targets, calendar: Calendar = .current) -> Int {
        reading(day, targets: targets, calendar: calendar).score
    }

    /// What held a day back most ("Protein", "Water", …), if anything did.
    static func weakest(_ day: Day, targets: Targets, calendar: Calendar = .current) -> String? {
        reading(day, targets: targets, calendar: calendar).boosts.first?.name
    }

    static func reading(_ day: Day, targets: Targets, calendar: Calendar = .current) -> AvatarMood.Reading {
        var s = HealthSnapshot()
        s.now = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day.date) ?? day.date
        s.waterOz = day.waterOz ?? 0
        s.waterTargetOz = targets.waterOz
        s.steps = day.steps ?? 0
        s.stepGoal = targets.steps
        s.proteinGrams = day.proteinGrams ?? 0
        s.proteinTarget = targets.protein
        s.caloriesIn = day.caloriesIn ?? 0
        s.calorieTarget = targets.calories
        s.sleepHours = day.sleepHours
        s.weighedInToday = day.weighedIn
        return AvatarMood.read(s, calendar: calendar)
    }

    // MARK: - Summary

    /// `readings` should reach a few weeks before `start` so the trend is
    /// settled by the first day of the week.
    static func summarize(
        days: [Day],
        readings: [WeightReading],
        targets: Targets,
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> Summary {
        let weekDays = days
            .filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: start)
                && calendar.startOfDay(for: $0.date) <= calendar.startOfDay(for: end) }
            .sorted { $0.date < $1.date }

        func avg(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let food = weekDays.compactMap { $0.caloriesIn }.filter { $0 > 0 }
        let protein = weekDays.compactMap { $0.proteinGrams }.filter { $0 > 0 }
        let water = weekDays.compactMap { $0.waterOz }.filter { $0 > 0 }
        let steps = weekDays.compactMap { $0.steps }.filter { $0 > 0 }.map(Double.init)
        let sleep = weekDays.compactMap { $0.sleepHours }.filter { $0 > 0 }

        let scores = weekDays.filter(\.hasData).map { DayScore(date: $0.date, score: score($0, targets: targets, calendar: calendar)) }

        // Weight: smoothed trend on the last weigh-in day at or before each end.
        let series = WeightChallengeEngine.dailySeries(readings, calendar: calendar)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let before = series.last { $0.day < startDay } ?? series.first { $0.day >= startDay && $0.day <= endDay }
        let after = series.last { $0.day <= endDay && $0.day >= startDay }
        var change: Double?
        var rate: Double?
        if let a = before, let b = after, b.day > a.day {
            change = b.trend - a.trend
            let span = Double(calendar.dateComponents([.day], from: a.day, to: b.day).day ?? 0)
            if span >= 3, let c = change { rate = c / span * 7 }
        }

        return Summary(
            start: startDay,
            end: endDay,
            days: weekDays,
            scores: scores,
            weightStart: before?.trend,
            weightEnd: after?.trend,
            weightChange: change,
            weeklyRate: rate,
            avgCalories: avg(food),
            avgProtein: avg(protein),
            avgWater: avg(water),
            avgSteps: avg(steps),
            avgSleep: avg(sleep),
            calorieDays: targets.calories > 0 ? food.filter { $0 <= targets.calories }.count : 0,
            proteinDays: protein.filter { $0 >= targets.protein * 0.9 }.count,
            waterDays: water.filter { $0 >= targets.waterOz * 0.9 }.count,
            stepDays: steps.filter { $0 >= Double(targets.steps) * 0.9 }.count,
            sleepDays: sleep.filter { $0 >= targets.sleepHours }.count,
            weighInDays: weekDays.filter(\.weighedIn).count,
            workoutsDone: weekDays.filter(\.workoutDone).count,
            foodLoggedDays: food.count
        )
    }

    // MARK: - One thing to fix

    enum FixArea: String, CaseIterable, Equatable {
        case logging, calories, protein, water, steps, sleep, weighIn, none
    }

    struct Fix: Equatable {
        let area: FixArea
        let headline: String
        let detail: String
    }

    /// The deterministic pick: each area's gap is its day-score weight ×
    /// the share of the week's days you missed it (water, steps, protein
    /// 20; calories, sleep 15; weigh-in 10). Biggest gap wins; ties go in
    /// FixArea order. Fewer than 4 days of food logged trumps everything —
    /// you can't fix what you can't see.
    static func biggestGap(_ s: Summary, targets: Targets) -> Fix {
        let n = 7.0

        if s.foodLoggedDays < 4 && !s.days.isEmpty {
            return Fix(area: .logging,
                       headline: "Log food every day",
                       detail: "Food was logged on \(s.foodLoggedDays) of 7 days. Snap or say every meal next week — even the messy ones — so the numbers can actually help.")
        }

        func missShare(_ hits: Int) -> Double { max(0, n - Double(hits)) / n }
        var gaps: [(FixArea, Double)] = [
            (.calories, 15 * missShare(s.calorieDays)),
            (.protein, 20 * missShare(s.proteinDays)),
            (.water, 20 * missShare(s.waterDays)),
            (.steps, 20 * missShare(s.stepDays)),
            (.sleep, s.avgSleep == nil ? 0 : 15 * missShare(s.sleepDays)),
            (.weighIn, 10 * missShare(s.weighInDays))
        ]
        // Stable: biggest first, FixArea order breaks ties.
        let order = FixArea.allCases
        gaps.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return (order.firstIndex(of: a.0) ?? 0) < (order.firstIndex(of: b.0) ?? 0)
        }
        guard let top = gaps.first, top.1 >= 4 else {
            return Fix(area: .none,
                       headline: "Run it back",
                       detail: "No real gaps this week — same plan, same habits. Consistency is the whole game.")
        }

        func i(_ v: Double?) -> String { v.map { Int($0.rounded()).formatted() } ?? "—" }
        switch top.0 {
        case .calories:
            return Fix(area: .calories, headline: "Stay inside the calorie budget",
                       detail: "Under \(i(targets.calories)) kcal on \(s.calorieDays) of 7 days, averaging \(i(s.avgCalories)). Decide dinner before 5 PM and leave 500 kcal for it.")
        case .protein:
            return Fix(area: .protein, headline: "Hit protein earlier",
                       detail: "Averaged \(i(s.avgProtein)) g of \(i(targets.protein)) g and hit it \(s.proteinDays) of 7 days. Start with 40 g at breakfast — a shake or eggs + Greek yogurt.")
        case .water:
            return Fix(area: .water, headline: "Drink earlier in the day",
                       detail: "Averaged \(i(s.avgWater)) of \(i(targets.waterOz)) oz and hit it \(s.waterDays) of 7 days. Finish the first bottle by 11 and the second by 2.")
        case .steps:
            return Fix(area: .steps, headline: "Walk Peaches after dinner",
                       detail: "Averaged \(i(s.avgSteps)) steps and hit \(targets.steps.formatted()) on \(s.stepDays) of 7 days. A 30-minute walk after dinner closes most of that gap.")
        case .sleep:
            return Fix(area: .sleep, headline: "Protect your sleep",
                       detail: "Averaged \(String(format: "%.1f", s.avgSleep ?? 0)) h and got 7+ on \(s.sleepDays) of 7 nights. Lights out by 10:30 on weeknights — it makes hunger easier too.")
        case .weighIn:
            return Fix(area: .weighIn, headline: "Weigh in every morning",
                       detail: "Weighed in \(s.weighInDays) of 7 days. Scale before coffee, every day — a steadier trend means fewer surprises.")
        case .logging, .none:
            return Fix(area: .none, headline: "Run it back", detail: "Same plan next week.")
        }
    }

    // MARK: - Prompt for Apple Intelligence

    static func promptText(_ s: Summary, targets: Targets, goalName: String?, daysToGoal: Int?) -> String {
        func i(_ v: Double?) -> String { v.map { String(Int($0.rounded())) } ?? "not logged" }
        var lines: [String] = []
        if let change = s.weightChange {
            lines.append("- Weight trend: \(String(format: "%+.1f", change)) lb this week")
        }
        lines.append("- Calories: avg \(i(s.avgCalories)) vs \(i(targets.calories)) target, under budget \(s.calorieDays) of 7 days, food logged \(s.foodLoggedDays) of 7 days")
        lines.append("- Protein: avg \(i(s.avgProtein)) g vs \(i(targets.protein)) g, hit \(s.proteinDays) of 7 days")
        lines.append("- Water: avg \(i(s.avgWater)) oz vs \(i(targets.waterOz)) oz, hit \(s.waterDays) of 7 days")
        lines.append("- Steps: avg \(i(s.avgSteps)) vs \(targets.steps), hit \(s.stepDays) of 7 days")
        if let sleep = s.avgSleep {
            lines.append("- Sleep: avg \(String(format: "%.1f", sleep)) h, 7+ h on \(s.sleepDays) of 7 nights")
        }
        lines.append("- Weighed in \(s.weighInDays) of 7 days; workouts done: \(s.workoutsDone)")
        if let goalName, let daysToGoal {
            lines.append("- Goal: \(goalName) in \(daysToGoal) days")
        }
        return lines.joined(separator: "\n")
    }
}
