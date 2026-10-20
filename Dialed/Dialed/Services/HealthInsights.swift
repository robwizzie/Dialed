//
//  HealthInsights.swift
//  Dialed
//
//  The math behind the Health tab's Body, Sleep and Nutrition pages:
//  sleep score and insights, nutrition score and insights, a readiness
//  estimate, stress, illness watch, tonight's sleep plan and baselines. Every score here is our own transparent
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
        /// Stage-by-stage segments across the whole night, when known.
        var segments: [HealthKitManager.SleepSegment] = []
        /// The stretches you were asleep — more than one when the night
        /// was split (you got up and went back to bed).
        var periods: [DateInterval] = []

        var efficiency: Double {
            inBedMinutes > 0 ? Double(asleepMinutes) / Double(inBedMinutes) : 0
        }
        var hours: Double { Double(asleepMinutes) / 60 }
    }

    /// Dialed's score, 0–100: duration (50), efficiency (20), deep + REM
    /// share (20), awakenings (10). Always Dialed's own number; the watch's
    /// score (Google / Fitbit) stays on `Night.vendorScore` for comparison.
    static func sleepScore(_ n: Night) -> Int {
        scoreBreakdown(n).total
    }

    /// The four parts of Dialed's sleep score, in points.
    struct ScoreBreakdown: Equatable {
        /// Time asleep toward 7.5 h, out of 50.
        var duration: Double
        /// Share of time in bed actually asleep (75 % → 0, 95 % → full), out of 20.
        var efficiency: Double
        /// Deep + REM share of sleep (40 % → full), out of 20. 12 when stages are unknown.
        var restorative: Double
        /// 10 minus 1.5 per wake-up, out of 10. 7 when unknown.
        var wakeUps: Double
        var stagesKnown: Bool
        var wakeUpsKnown: Bool

        var total: Int { Int((duration + efficiency + restorative + wakeUps).rounded()) }
    }

    static func scoreBreakdown(_ n: Night) -> ScoreBreakdown {
        let duration = min(1, Double(n.asleepMinutes) / 450) * 50
        let efficiency = max(0, min(1, (n.efficiency - 0.75) / 0.2)) * 20
        var restorative = 12.0
        var stagesKnown = false
        if let deep = n.deepMinutes, let rem = n.remMinutes, n.asleepMinutes > 0 {
            restorative = max(0, min(1, Double(deep + rem) / Double(n.asleepMinutes) / 0.4)) * 20
            stagesKnown = true
        }
        let wakes = n.awakenings.map { max(0, 10 - Double($0) * 1.5) } ?? 7
        return ScoreBreakdown(duration: duration, efficiency: efficiency, restorative: restorative, wakeUps: wakes,
                              stagesKnown: stagesKnown, wakeUpsKnown: n.awakenings != nil)
    }

    /// One night from every session that woke you on the same day. Watches
    /// split a night when you get up for a while; this joins the pieces back
    /// into one (the gap counts as awake), drops overlapping duplicates from
    /// a second source, and leaves out sessions hours away (naps).
    static func combine(_ sessions: [Night], maxGap: TimeInterval = 3 * 3600) -> Night? {
        // Overlapping sessions describe the same sleep: keep the fuller one.
        var pieces: [Night] = []
        for s in sessions.sorted(by: { $0.bedtime < $1.bedtime }) {
            if let last = pieces.last, s.bedtime < last.wakeTime {
                if (s.asleepMinutes, s.segments.count) > (last.asleepMinutes, last.segments.count) {
                    pieces[pieces.count - 1] = s
                }
            } else {
                pieces.append(s)
            }
        }
        guard let mainIndex = pieces.indices.max(by: { pieces[$0].asleepMinutes < pieces[$1].asleepMinutes }) else { return nil }
        var lo = mainIndex, hi = mainIndex
        while lo > 0, pieces[lo].bedtime.timeIntervalSince(pieces[lo - 1].wakeTime) <= maxGap { lo -= 1 }
        while hi < pieces.count - 1, pieces[hi + 1].bedtime.timeIntervalSince(pieces[hi].wakeTime) <= maxGap { hi += 1 }
        let night = Array(pieces[lo...hi])
        if night.count == 1 {
            var only = night[0]
            if only.periods.isEmpty { only.periods = [DateInterval(start: only.bedtime, end: only.wakeTime)] }
            return only
        }

        func sum(_ value: (Night) -> Int?) -> Int? {
            let known = night.compactMap(value)
            return known.isEmpty ? nil : known.reduce(0, +)
        }
        var gaps: [HealthKitManager.SleepSegment] = []
        for (a, b) in zip(night, night.dropFirst()) {
            gaps.append(.init(start: a.wakeTime, end: b.bedtime, stage: .awake))
        }
        let gapMinutes = gaps.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        let first = night[0], last = night[night.count - 1]
        let staged = night.allSatisfy { !$0.segments.isEmpty }
        return Night(
            wakeDay: main(night).wakeDay,
            bedtime: first.bedtime, wakeTime: last.wakeTime,
            inBedMinutes: night.reduce(0) { $0 + $1.inBedMinutes } + gapMinutes,
            asleepMinutes: night.reduce(0) { $0 + $1.asleepMinutes },
            deepMinutes: sum(\.deepMinutes), remMinutes: sum(\.remMinutes), lightMinutes: sum(\.lightMinutes),
            awakeMinutes: (sum(\.awakeMinutes) ?? 0) + gapMinutes,
            awakenings: (sum(\.awakenings) ?? 0) + gaps.count,
            // A watch score covers one piece, not the whole night.
            vendorScore: nil,
            segments: staged ? (night.flatMap(\.segments) + gaps).sorted { $0.start < $1.start } : [],
            periods: night.map { DateInterval(start: $0.bedtime, end: $0.wakeTime) })
    }

    private static func main(_ night: [Night]) -> Night {
        night.max { $0.asleepMinutes < $1.asleepMinutes } ?? night[0]
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

    // MARK: - Tonight's sleep

    struct SleepPlan: Equatable {
        /// Hours to aim for tonight: your need plus a slice of the debt.
        let targetHours: Double
        /// Sleep owed over the last week (need − actual, never negative per night).
        let debtHours: Double
        /// When to be asleep, as minutes past midnight (may wrap the day).
        let bedtimeMinutes: Int
        /// The wake time it's planned around, minutes past midnight.
        let wakeMinutes: Int
    }

    /// Tonight's target and bedtime from your usual wake time (median of
    /// the last week) and a third of this week's sleep debt (capped at an
    /// extra hour — more than that just wrecks the next night). nil with
    /// fewer than three nights.
    static func sleepPlan(history: [Night], needHours: Double = 7.5, calendar: Calendar = .current) -> SleepPlan? {
        let week = history.suffix(7)
        guard week.count >= 3 else { return nil }
        let debt = week.map { max(0, needHours - $0.hours) }.reduce(0, +)
        let target = needHours + min(1, debt / 3)
        let wakes = week.map { n -> Int in
            let c = calendar.dateComponents([.hour, .minute], from: n.wakeTime)
            return (c.hour ?? 7) * 60 + (c.minute ?? 0)
        }.sorted()
        let wake = wakes[wakes.count / 2]
        let bed = ((wake - Int((target * 60).rounded())) % 1440 + 1440) % 1440
        return SleepPlan(targetHours: target, debtHours: debt, bedtimeMinutes: bed, wakeMinutes: wake)
    }

    // MARK: - Stress

    struct Stress: Equatable {
        /// 0–100, higher = more physiological stress.
        let score: Int
        let contributors: [Contributor]

        struct Contributor: Equatable, Identifiable {
            let name: String
            /// 0 (relaxing) … 0.5 (your normal) … 1 (stressing).
            let load: Double
            let detail: String
            var id: String { name }
        }

        var label: String {
            switch score {
            case ..<30:  return "Calm"
            case 30..<55: return "Balanced"
            case 55..<75: return "Elevated"
            default:     return "High"
            }
        }
    }

    /// Body stress from how far today's signals sit from your baseline:
    /// suppressed HRV (heaviest), raised resting HR, short sleep and faster
    /// breathing. Your normal lands around 40 ("Balanced"). nil with fewer
    /// than two signals.
    static func stress(hrv: Double?, hrvBaseline: [Double],
                       restingHR: Double?, rhrBaseline: [Double],
                       sleepHours: Double?,
                       respiratory: Double?, respBaseline: [Double]) -> Stress? {
        var parts: [(weight: Double, c: Stress.Contributor)] = []
        func clamp(_ x: Double) -> Double { max(0, min(1, x)) }

        if let pct = percentChange(hrv, baseline: hrvBaseline), let hrv {
            parts.append((40, .init(name: "HRV", load: clamp(0.5 - pct / 40),
                                    detail: "\(Int(hrv.rounded())) ms, \(signed(pct, "%")) vs usual")))
        }
        if let rhr = restingHR, let avg = mean(rhrBaseline) {
            let d = rhr - avg
            parts.append((25, .init(name: "Resting HR", load: clamp(0.5 + d / 10),
                                    detail: "\(Int(rhr.rounded())) bpm, \(signed(d, " bpm")) vs usual")))
        }
        if let h = sleepHours {
            parts.append((20, .init(name: "Sleep", load: clamp(0.5 + (7.5 - h) / 4),
                                    detail: String(format: "%.1f h last night", h))))
        }
        if let r = respiratory, let avg = mean(respBaseline) {
            let d = r - avg
            parts.append((15, .init(name: "Breathing", load: clamp(0.5 + d / 3),
                                    detail: String(format: "%.0f rpm, %@ vs usual", r, signed(d, " rpm", decimals: 1)))))
        }
        guard parts.count >= 2 else { return nil }
        let avg = parts.reduce(0) { $0 + $1.weight * $1.c.load } / parts.reduce(0) { $0 + $1.weight }
        return Stress(score: Int((100 * pow(avg, 1.3)).rounded()), contributors: parts.map(\.c))
    }

    private static func signed(_ v: Double, _ unit: String, decimals: Int = 0) -> String {
        let n = String(format: "%.\(decimals)f", abs(v))
        if Double(n) == 0 { return "±0\(unit)" }
        return (v > 0 ? "+" : "−") + n + unit
    }

    // MARK: - Illness watch

    struct IllnessCheck: Equatable {
        enum Level: Int, Comparable {
            case clear, watch, alert
            static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        }

        struct Signal: Equatable, Identifiable {
            let name: String
            let icon: String
            let value: String
            let usual: String
            let flagged: Bool
            var id: String { name }
        }

        let level: Level
        let signals: [Signal]

        var flaggedCount: Int { signals.filter(\.flagged).count }

        var headline: String {
            switch level {
            case .clear: return "All clear"
            case .watch: return "Something's off"
            case .alert: return "Your body may be fighting something"
            }
        }

        var advice: String {
            switch level {
            case .clear: return "Your overnight vitals are within your normal range."
            case .watch: return "\(flaggedCount) signals are outside your normal range. Go easy today and prioritise sleep."
            case .alert: return "Several vitals moved together the way they do before a cold. Rest, hydrate, and skip hard training."
            }
        }
    }

    /// Compares last night's vitals with your own baseline (the days before)
    /// — the pattern wearables use to spot illness a day or two early: resting
    /// HR up, HRV down, breathing faster, skin warmer, oxygen lower. Two
    /// signals off = watch; three, or a fever-like temperature with another,
    /// = alert. nil with fewer than two signals or too little history.
    static func illnessCheck(restingHR: Double?, rhrBaseline: [Double],
                             hrv: Double?, hrvBaseline: [Double],
                             respiratory: Double?, respBaseline: [Double],
                             skinTemp: Double?, skinTempBaseline: [Double],
                             spO2: Double?, spO2Baseline: [Double]) -> IllnessCheck? {
        let minDays = 4
        var signals: [IllnessCheck.Signal] = []
        var feverish = false

        /// Flags when `value` sits `threshold` past the mean in the bad
        /// direction — or 1.5 SD, if you normally swing more than that.
        func off(_ value: Double, _ base: [Double], threshold: Double, worseWhenUp: Bool) -> Bool {
            guard let m = mean(base) else { return false }
            let limit = max(threshold, 1.5 * (standardDeviation(base) ?? 0))
            return worseWhenUp ? value - m >= limit : m - value >= limit
        }

        if let v = restingHR, rhrBaseline.count >= minDays, let m = mean(rhrBaseline) {
            signals.append(.init(name: "Resting heart rate", icon: "heart.fill",
                                 value: "\(Int(v.rounded())) bpm", usual: "usual \(Int(m.rounded()))",
                                 flagged: off(v, rhrBaseline, threshold: 3, worseWhenUp: true)))
        }
        if let v = hrv, hrvBaseline.count >= minDays, let m = mean(hrvBaseline) {
            signals.append(.init(name: "HRV", icon: "waveform.path.ecg",
                                 value: "\(Int(v.rounded())) ms", usual: "usual \(Int(m.rounded()))",
                                 flagged: off(v, hrvBaseline, threshold: m * 0.15, worseWhenUp: false)))
        }
        if let v = respiratory, respBaseline.count >= minDays, let m = mean(respBaseline) {
            signals.append(.init(name: "Breathing rate", icon: "lungs.fill",
                                 value: String(format: "%.1f rpm", v), usual: String(format: "usual %.1f", m),
                                 flagged: off(v, respBaseline, threshold: 1, worseWhenUp: true)))
        }
        if let v = skinTemp, skinTempBaseline.count >= minDays, let m = mean(skinTempBaseline) {
            let flagged = off(v, skinTempBaseline, threshold: 0.5, worseWhenUp: true)
            feverish = v - m >= 0.8
            signals.append(.init(name: "Skin temperature", icon: "thermometer.medium",
                                 value: String(format: "%+.1f °C", v - m), usual: "vs your baseline",
                                 flagged: flagged))
        }
        if let v = spO2, spO2Baseline.count >= minDays, let m = mean(spO2Baseline) {
            signals.append(.init(name: "Blood oxygen", icon: "drop.fill",
                                 value: String(format: "%.0f%%", v), usual: String(format: "usual %.0f", m),
                                 flagged: off(v, spO2Baseline, threshold: 2, worseWhenUp: false) || v < 92))
        }
        guard signals.count >= 2 else { return nil }
        let flagged = signals.filter(\.flagged).count
        let level: IllnessCheck.Level = flagged >= 3 || (feverish && flagged >= 2) ? .alert : (flagged == 2 ? .watch : .clear)
        return IllnessCheck(level: level, signals: signals)
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
                               text: "\(Int(today.calories - today.calorieTarget)) calories over budget. A long walk burns ~300."))
        }
        return out
    }

    /// First and last meal of the day.
    static func eatingWindow(_ times: [Date]) -> (start: Date, end: Date)? {
        guard let first = times.min(), let last = times.max(), last > first else { return nil }
        return (first, last)
    }
}
