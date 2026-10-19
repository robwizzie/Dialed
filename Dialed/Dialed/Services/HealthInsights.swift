//
//  HealthInsights.swift
//  Dialed
//
//  The math behind the Health tab's Body, Sleep and Nutrition pages:
//  sleep score and insights, nutrition score and insights, a readiness
//  estimate, and baselines. Every score here is our own transparent
//  estimate from your real numbers, labeled as such in the UI.
//  Pure Foundation, unit-tested.
//

import Foundation

enum HealthInsights {

    struct DayValue: Equatable {
        let date: Date
        let value: Double
    }

    struct Insight: Equatable, Identifiable {
        enum Tone: String { case good, neutral, watch }
        let icon: String
        let tone: Tone
        let text: String
        var id: String { text }
    }

    // MARK: - Shared

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        return (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(values.count - 1)).squareRoot()
    }

    /// Percent change of `value` against the mean of `baseline`.
    static func percentChange(_ value: Double?, baseline: [Double]) -> Double? {
        guard let value, let m = mean(baseline), m != 0 else { return nil }
        return (value - m) / m * 100
    }

    static func label(for score: Int) -> String {
        switch score {
        case 85...:   return "Excellent"
        case 70..<85: return "Good"
        case 50..<70: return "Fair"
        default:      return "Low"
        }
    }

    // MARK: - Sleep

    struct Night: Equatable {
        let wakeDay: Date
        let bedtime: Date
        let wakeTime: Date
        let inBedMinutes: Int
        let asleepMinutes: Int
        let deepMinutes: Int?
        let remMinutes: Int?
        let lightMinutes: Int?
        let awakeMinutes: Int?
        let awakenings: Int?
        /// The watch's own score, when it gives one.
        let vendorScore: Int?

        var efficiency: Double {
            inBedMinutes > 0 ? Double(asleepMinutes) / Double(inBedMinutes) : 0
        }
        var hours: Double { Double(asleepMinutes) / 60 }
    }

    /// 0–100: duration (50), efficiency (20), deep + REM share (20),
    /// awakenings (10). Uses the watch's score when it has one.
    static func sleepScore(_ n: Night) -> Int {
        if let v = n.vendorScore { return v }
        let duration = min(1, Double(n.asleepMinutes) / 450) * 50
        let efficiency = max(0, min(1, (n.efficiency - 0.75) / 0.2)) * 20
        var restorative = 12.0
        if let deep = n.deepMinutes, let rem = n.remMinutes, n.asleepMinutes > 0 {
            restorative = max(0, min(1, Double(deep + rem) / Double(n.asleepMinutes) / 0.4)) * 20
        }
        let wakes = n.awakenings.map { max(0, 10 - Double($0) * 1.5) } ?? 7
        return Int((duration + efficiency + restorative + wakes).rounded())
    }

    /// Minutes past 6 PM, so bedtimes either side of midnight compare.
    static func bedtimeMinutes(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        return m < 18 * 60 ? m + 6 * 60 : m - 18 * 60
    }

    static func sleepInsights(last: Night, history: [Night], calendar: Calendar = .current) -> [Insight] {
        let prior = history.filter { $0.wakeDay < last.wakeDay }.suffix(7)
        var out: [Insight] = []

        if let avg = mean(prior.map(\.hours)) {
            let diff = (last.hours - avg) * 60
            if abs(diff) >= 20 {
                out.append(Insight(icon: "moon.fill", tone: diff > 0 ? .good : .watch,
                                   text: "You slept \(Int(abs(diff).rounded())) min \(diff > 0 ? "more" : "less") than your weekly average."))
            }
        }
        if let deep = last.deepMinutes, let avgDeep = mean(prior.compactMap { $0.deepMinutes.map(Double.init) }) {
            let diff = Double(deep) - avgDeep
            if abs(diff) >= 10 {
                out.append(Insight(icon: "waveform.path", tone: diff > 0 ? .good : .watch,
                                   text: "Deep sleep was \(diff > 0 ? "higher" : "lower") than usual (\(deep) min vs \(Int(avgDeep)))."))
            }
        }
        let beds = (prior + [last]).map { bedtimeMinutes($0.bedtime, calendar: calendar) }
        if let sd = standardDeviation(beds) {
            out.append(sd <= 30
                ? Insight(icon: "checkmark.shield.fill", tone: .good, text: "Your bedtime is consistent — within ±\(Int(sd)) min.")
                : Insight(icon: "clock.badge.exclamationmark", tone: .watch, text: "Bedtime swings ±\(Int(sd)) min. A steadier bedtime improves deep sleep."))
        }
        let debt = prior.map { max(0, 7.5 - $0.hours) }.reduce(0, +) + max(0, 7.5 - last.hours)
        if debt >= 2 {
            out.append(Insight(icon: "battery.25", tone: .watch,
                               text: String(format: "%.1f h of sleep debt this week. Aim for lights out by 10:30.", debt)))
        }
        if last.efficiency < 0.85 && last.inBedMinutes > 0 {
            out.append(Insight(icon: "sun.max.fill", tone: .neutral,
                               text: "\(Int(last.efficiency * 100))% of your time in bed was asleep. Less screen time before bed helps."))
        }
        return out
    }

    // MARK: - Readiness

    /// 0–100 from HRV and resting HR against your 14-day baseline, plus
    /// last night's sleep. nil without enough history.
    static func readiness(hrv: Double?, hrvBaseline: [Double], restingHR: Double?, rhrBaseline: [Double], sleepHours: Double?) -> Int? {
        var score = 60.0
        var inputs = 0
        if let hrvPct = percentChange(hrv, baseline: hrvBaseline) {
            score += max(-20, min(20, hrvPct))
            inputs += 1
        }
        if let rhrPct = percentChange(restingHR, baseline: rhrBaseline) {
            score -= max(-12, min(12, rhrPct * 2))
            inputs += 1
        }
        if let h = sleepHours {
            score += max(-15, min(10, (h - 7) * 8))
            inputs += 1
        }
        guard inputs >= 2 else { return nil }
        return Int(max(0, min(100, score)).rounded())
    }

    // MARK: - Nutrition

    struct NutritionDay: Equatable {
        var calories: Double
        var calorieTarget: Double
        var protein: Double
        var proteinTarget: Double
        var waterOz: Double
        var waterTargetOz: Double
        var fiber: Double?
    }

    /// 0–100: calories near/under budget (35), protein (35), water (20),
    /// fiber (10, or 5 when unknown).
    static func nutritionScore(_ d: NutritionDay) -> Int {
        var cal = 0.0
        if d.calorieTarget > 0, d.calories > 0 {
            let ratio = d.calories / d.calorieTarget
            cal = ratio <= 1.05 ? (ratio >= 0.7 ? 35 : 35 * ratio / 0.7) : max(0, 35 - (ratio - 1.05) * 140)
        }
        let protein = d.proteinTarget > 0 ? min(1, d.protein / d.proteinTarget) * 35 : 0
        let water = d.waterTargetOz > 0 ? min(1, d.waterOz / d.waterTargetOz) * 20 : 0
        let fiber = d.fiber.map { min(1, $0 / 30) * 10 } ?? 5
        return Int((cal + protein + water + fiber).rounded())
    }

    /// Consecutive days, ending with the most recent, at ≥ 90% of target.
    static func streak(_ values: [Double], target: Double) -> Int {
        guard target > 0 else { return 0 }
        var n = 0
        for v in values.reversed() {
            if v >= target * 0.9 { n += 1 } else { break }
        }
        return n
    }

    static func nutritionInsights(
        today: NutritionDay,
        proteinHistory: [Double],
        mealTimes: [Date],
        expectedFraction: Double,
        calendar: Calendar = .current
    ) -> [Insight] {
        var out: [Insight] = []
        let streakDays = streak(proteinHistory, target: today.proteinTarget)
        if streakDays >= 2 {
            out.append(Insight(icon: "chart.line.uptrend.xyaxis", tone: .good,
                               text: "You hit your protein target \(streakDays) days in a row."))
        } else if today.proteinTarget > today.protein {
            out.append(Insight(icon: "fork.knife", tone: .neutral,
                               text: "\(Int(today.proteinTarget - today.protein)) g protein to go — a shake or chicken breast covers most of it."))
        }
        let waterPace = today.waterTargetOz * expectedFraction
        if today.waterOz < waterPace - 8 {
            out.append(Insight(icon: "drop.fill", tone: .watch,
                               text: "Hydration is \(Int(waterPace - today.waterOz)) oz behind pace. Add a bottle with your next meal."))
        }
        if let last = mealTimes.max(), calendar.component(.hour, from: last) >= 21 {
            out.append(Insight(icon: "moon.fill", tone: .watch,
                               text: "Late meals (after 9 PM) tend to cut into deep sleep."))
        }
        if let fiber = today.fiber, fiber < 25 {
            out.append(Insight(icon: "leaf.fill", tone: .neutral,
                               text: "Fiber is \(Int(fiber)) g. Beans, berries or oats get you to 30 g and keep you full."))
        }
        if today.calorieTarget > 0, today.calories > today.calorieTarget * 1.05 {
            out.append(Insight(icon: "flame.fill", tone: .watch,
                               text: "\(Int(today.calories - today.calorieTarget)) kcal over budget. A long walk with Peaches burns ~300."))
        }
        return out
    }

    /// First and last meal of the day.
    static func eatingWindow(_ times: [Date]) -> (start: Date, end: Date)? {
        guard let first = times.min(), let last = times.max(), last > first else { return nil }
        return (first, last)
    }
}
