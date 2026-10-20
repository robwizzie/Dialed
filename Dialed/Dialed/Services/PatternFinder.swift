//
//  PatternFinder.swift
//  Dialed
//
//  The habits hiding in your last few weeks: "Weekends average 600 more
//  calories", "You sleep 40 min less after late meals", "The morning
//  after drinks the scale reads 1.2 lb higher". Each pattern compares two
//  groups of days and only speaks up with enough days on both sides
//  (3+) and a gap big enough to matter, so it never reports noise.
//  Pure Foundation, unit-tested; PatternLoader builds the days.
//

import Foundation

enum PatternFinder {

    /// One day, as Dialed saw it. nil = not logged / not known.
    struct Day: Equatable {
        var date: Date
        /// Eaten that day. Days under `minimumLoggedCalories` count as
        /// not logged (half a day of logging isn't a low day).
        var calories: Double?
        var protein: Double?
        var miles: Double?
        /// Sleep the night *before* this day (ending this morning).
        var sleepMinutes: Double?
        /// When that night started.
        var bedtime: Date?
        /// Time of the day's last meal.
        var lastMeal: Date?
        var workout = false
        /// Morning weight.
        var weight: Double?
        var drinks: Double = 0
        /// Calories exercise earned back.
        var earned: Double = 0
    }

    struct Pattern: Equatable, Identifiable {
        let id: String
        let symbol: String
        /// "Weekends average 600 more calories"
        let title: String
        /// "2,450 on weekends vs 1,850 on weekdays · 8 vs 20 days"
        let detail: String
        /// How sure and how big; higher first.
        let strength: Double
        /// Whether the gap is in your favor (for tint): true good, false a leak.
        let isGood: Bool
        /// Days on each side of the comparison.
        let samples: [Int]
    }

    static let minimumLoggedCalories = 800.0
    static let minimumSamples = 3

    // MARK: - Find

    static func find(_ days: [Day], mileGoal: Double = 1, calendar: Calendar = .current) -> [Pattern] {
        let sorted = days.sorted { $0.date < $1.date }
        var byDay: [Date: Day] = [:]
        for d in sorted { byDay[calendar.startOfDay(for: d.date)] = d }
        func next(_ d: Day) -> Day? {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: d.date)).flatMap { byDay[$0] }
        }
        let logged = sorted.filter { ($0.calories ?? 0) >= minimumLoggedCalories }

        let found: [Pattern?] = [
            weekendCalories(logged, calendar: calendar),
            lateMealSleep(sorted, next: next, calendar: calendar),
            workoutSleep(sorted, next: next),
            drinksWeight(sorted, next: next),
            proteinCalories(logged),
            mileCalories(logged, goal: mileGoal),
            shortSleepCalories(logged)
        ]
        return found.compactMap { $0 }.sorted { $0.strength > $1.strength }
    }

    // MARK: - The patterns

    static func weekendCalories(_ logged: [Day], calendar: Calendar) -> Pattern? {
        let isWeekend = { (d: Day) in calendar.isDateInWeekend(d.date) }
        guard let c = compare(logged.filter(isWeekend).compactMap(\.calories),
                              logged.filter { !isWeekend($0) }.compactMap(\.calories), threshold: 150) else { return nil }
        let more = c.diff > 0
        return Pattern(
            id: "weekend-calories", symbol: "calendar",
            title: "Weekends average \(cal(abs(c.diff))) \(more ? "more" : "fewer") calories",
            detail: "\(cal(c.a)) on weekends vs \(cal(c.b)) on weekdays · \(c.na) vs \(c.nb) days",
            strength: c.strength, isGood: !more, samples: [c.na, c.nb])
    }

    /// Last meal after 8:30 PM → that night's sleep (next day's record).
    static func lateMealSleep(_ days: [Day], next: (Day) -> Day?, calendar: Calendar) -> Pattern? {
        var late: [Double] = [], early: [Double] = []
        for d in days {
            guard let meal = d.lastMeal, let sleep = next(d)?.sleepMinutes else { continue }
            let c = calendar.dateComponents([.hour, .minute], from: meal)
            let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            // After midnight still counts as late.
            if minutes >= 20 * 60 + 30 || minutes < 4 * 60 { late.append(sleep) } else { early.append(sleep) }
        }
        guard let c = compare(late, early, threshold: 20) else { return nil }
        let less = c.diff < 0
        return Pattern(
            id: "late-meal-sleep", symbol: "moon.zzz.fill",
            title: "You sleep \(minutes(abs(c.diff))) \(less ? "less" : "more") after late meals",
            detail: "\(hours(c.a)) after eating past 8:30 PM vs \(hours(c.b)) otherwise · \(c.na) vs \(c.nb) nights",
            strength: c.strength, isGood: !less, samples: [c.na, c.nb])
    }

    static func workoutSleep(_ days: [Day], next: (Day) -> Day?) -> Pattern? {
        var trained: [Double] = [], rest: [Double] = []
        for d in days {
            guard let sleep = next(d)?.sleepMinutes else { continue }
            if d.workout { trained.append(sleep) } else { rest.append(sleep) }
        }
        guard let c = compare(trained, rest, threshold: 20) else { return nil }
        let more = c.diff > 0
        return Pattern(
            id: "workout-sleep", symbol: "dumbbell.fill",
            title: "You sleep \(minutes(abs(c.diff))) \(more ? "more" : "less") on workout days",
            detail: "\(hours(c.a)) after a workout vs \(hours(c.b)) on rest days · \(c.na) vs \(c.nb) nights",
            strength: c.strength, isGood: more, samples: [c.na, c.nb])
    }

    /// Drinks on a day → next morning's weight change.
    static func drinksWeight(_ days: [Day], next: (Day) -> Day?) -> Pattern? {
        var drank: [Double] = [], dry: [Double] = []
        for d in days {
            guard let w = d.weight, let tomorrow = next(d)?.weight else { continue }
            if d.drinks > 0 { drank.append(tomorrow - w) } else { dry.append(tomorrow - w) }
        }
        guard let c = compare(drank, dry, threshold: 0.4) else { return nil }
        let up = c.diff > 0
        return Pattern(
            id: "drinks-weight", symbol: "wineglass.fill",
            title: "The morning after drinks, the scale reads \(pounds(abs(c.diff))) \(up ? "higher" : "lower")",
            detail: "\(signed(c.a)) overnight after drinking vs \(signed(c.b)) otherwise · \(c.na) vs \(c.nb) mornings. Mostly water, but it hides real progress.",
            strength: c.strength, isGood: !up, samples: [c.na, c.nb])
    }

    /// Top half of protein days vs bottom half → calories.
    static func proteinCalories(_ logged: [Day]) -> Pattern? {
        let withProtein = logged.filter { ($0.protein ?? 0) > 0 }
        guard withProtein.count >= minimumSamples * 2 else { return nil }
        let median = withProtein.compactMap(\.protein).sorted()[withProtein.count / 2]
        let high = withProtein.filter { ($0.protein ?? 0) >= median }
        let low = withProtein.filter { ($0.protein ?? 0) < median }
        guard let c = compare(high.compactMap(\.calories), low.compactMap(\.calories), threshold: 150) else { return nil }
        let fewer = c.diff < 0
        return Pattern(
            id: "protein-calories", symbol: "fork.knife",
            title: "On high-protein days (\(Int(median.rounded()))+ g) you eat \(cal(abs(c.diff))) \(fewer ? "fewer" : "more") calories",
            detail: "\(cal(c.a)) vs \(cal(c.b)) on lower-protein days · \(c.na) vs \(c.nb) days",
            strength: c.strength, isGood: fewer, samples: [c.na, c.nb])
    }

    static func mileCalories(_ logged: [Day], goal: Double) -> Pattern? {
        let known = logged.filter { $0.miles != nil }
        let done = known.filter { ($0.miles ?? 0) >= goal }
        let missed = known.filter { ($0.miles ?? 0) < goal }
        guard let c = compare(done.compactMap(\.calories), missed.compactMap(\.calories), threshold: 150) else { return nil }
        let fewer = c.diff < 0
        return Pattern(
            id: "mile-calories", symbol: "figure.walk",
            title: "Days you get your mile, you eat \(cal(abs(c.diff))) \(fewer ? "fewer" : "more") calories",
            detail: "\(cal(c.a)) with the mile vs \(cal(c.b)) without · \(c.na) vs \(c.nb) days",
            strength: c.strength, isGood: fewer, samples: [c.na, c.nb])
    }

    /// A short night (< 6.5 h) → that day's calories.
    static func shortSleepCalories(_ logged: [Day]) -> Pattern? {
        let known = logged.filter { $0.sleepMinutes != nil }
        let short = known.filter { ($0.sleepMinutes ?? 0) < 390 }
        let rested = known.filter { ($0.sleepMinutes ?? 0) >= 390 }
        guard let c = compare(short.compactMap(\.calories), rested.compactMap(\.calories), threshold: 150) else { return nil }
        let more = c.diff > 0
        return Pattern(
            id: "short-sleep-calories", symbol: "bed.double.fill",
            title: "After under 6½ hours of sleep you eat \(cal(abs(c.diff))) \(more ? "more" : "fewer") calories",
            detail: "\(cal(c.a)) after a short night vs \(cal(c.b)) after a full one · \(c.na) vs \(c.nb) days",
            strength: c.strength, isGood: !more, samples: [c.na, c.nb])
    }

    // MARK: - Comparing two groups

    struct Comparison {
        let a: Double, b: Double, na: Int, nb: Int
        var diff: Double { a - b }
        let strength: Double
    }

    /// Averages of two groups, or nil when either is too small or the gap
    /// is under `threshold`. Strength grows with the gap and the samples.
    static func compare(_ groupA: [Double], _ groupB: [Double], threshold: Double) -> Comparison? {
        guard groupA.count >= minimumSamples, groupB.count >= minimumSamples else { return nil }
        let a = groupA.reduce(0, +) / Double(groupA.count)
        let b = groupB.reduce(0, +) / Double(groupB.count)
        guard abs(a - b) >= threshold else { return nil }
        let confidence = min(1, Double(min(groupA.count, groupB.count)) / 6)
        return Comparison(a: a, b: b, na: groupA.count, nb: groupB.count, strength: abs(a - b) / threshold * confidence)
    }

    // MARK: - Plain numbers

    /// 612 → "600", 1,847 → "1,850"
    static func cal(_ v: Double) -> String { (Int((v / 50).rounded()) * 50).formatted() }
    /// 38 → "40 min", 75 → "1 h 15 min"
    static func minutes(_ v: Double) -> String {
        let m = Int((v / 5).rounded()) * 5
        return m >= 60 ? "\(m / 60) h\(m % 60 == 0 ? "" : " \(m % 60) min")" : "\(m) min"
    }
    /// 412 → "6.9 h"
    static func hours(_ minutes: Double) -> String { String(format: "%.1f h", minutes / 60) }
    static func pounds(_ v: Double) -> String { String(format: "%.1f lb", v) }
    static func signed(_ v: Double) -> String { (v >= 0 ? "+" : "−") + String(format: "%.1f lb", abs(v)) }
}
