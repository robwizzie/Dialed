//
//  WeightChallengeEngine.swift
//  Dialed
//
//  Pure math for the weight-loss challenge. No SwiftData, no HealthKit —
//  callers hand in merged weight readings and get back where you stand,
//  whether you're on pace, where the trend lands you on the final day, and
//  who's winning. Fully unit-tested.
//

import Foundation

/// One scale reading from any source, in lbs.
struct WeightReading: Equatable, Identifiable {
    enum Source: String, Equatable {
        case healthKit
        case googleHealth
        case manual

        var displayName: String {
            switch self {
            case .healthKit: return "Apple Health"
            case .googleHealth: return "Google Health"
            case .manual:    return "Manual"
            }
        }
    }

    var id: String { "\(source.rawValue)-\(date.timeIntervalSince1970)" }
    let date: Date
    let pounds: Double
    let source: Source
}

enum WeightChallengeEngine {

    /// Calories per pound of body fat — the classic rule of thumb.
    static let kcalPerPound: Double = 3_500

    struct DailyWeight: Equatable, Identifiable {
        var id: Date { day }
        let day: Date
        /// Morning (earliest) reading of the day.
        let pounds: Double
        /// Exponentially smoothed trend weight — irons out water swings.
        let trend: Double
    }

    enum Leader: Equatable {
        case you
        case friend
        case tied
        case unknown
    }

    struct FriendProgress: Equatable {
        let startWeight: Double
        let currentWeight: Double
        let lostLbs: Double
        let lostPercent: Double
        let lastWeighIn: Date
    }

    struct Progress: Equatable {
        let startWeight: Double?
        let currentWeight: Double?
        let trendWeight: Double?
        let lostLbs: Double
        let lostPercent: Double

        /// 1-based day of the challenge, clamped to [1, totalDays].
        let dayNumber: Int
        let totalDays: Int
        let daysLeft: Int
        let fractionElapsed: Double

        let goalLossLbs: Double
        /// Loss you'd have if you were exactly on a straight-line pace.
        let expectedLossByNow: Double
        /// Positive = ahead of pace.
        let paceDelta: Double

        /// Loss on the final day if the current trend holds. nil without
        /// at least three weigh-in days to fit a line through.
        let projectedLossAtEnd: Double?
        /// Average lbs per week over the challenge so far (positive = losing).
        let weeklyRate: Double?
        /// kcal/day deficit needed from here to hit the goal. 0 when the goal
        /// is already reached.
        let requiredDailyDeficit: Double

        let friend: FriendProgress?
        let leader: Leader
        /// Lead in the scoring unit (lbs or %), always ≥ 0.
        let margin: Double

        let weighedInToday: Bool
        /// Consecutive days (ending today or yesterday) with a weigh-in.
        let weighInStreak: Int

        let series: [DailyWeight]

        var goalProgress: Double {
            guard goalLossLbs > 0 else { return 0 }
            return max(0, min(1, lostLbs / goalLossLbs))
        }

        var isFinished: Bool { daysLeft == 0 && fractionElapsed >= 1 }
    }

    // MARK: - Daily series

    /// Collapse raw readings into one per calendar day (earliest reading wins
    /// — morning weight is the most repeatable) and attach a smoothed trend.
    static func dailySeries(
        _ readings: [WeightReading],
        calendar: Calendar = .current,
        smoothing: Double = 0.25
    ) -> [DailyWeight] {
        var earliestByDay: [Date: WeightReading] = [:]
        for r in readings where r.pounds.isFinite && r.pounds > 0 {
            let day = calendar.startOfDay(for: r.date)
            if let existing = earliestByDay[day], existing.date <= r.date { continue }
            earliestByDay[day] = r
        }
        var trend: Double?
        return earliestByDay.keys.sorted().map { day in
            let lbs = earliestByDay[day]!.pounds
            let next = trend.map { $0 + smoothing * (lbs - $0) } ?? lbs
            trend = next
            return DailyWeight(day: day, pounds: lbs, trend: next)
        }
    }

    // MARK: - Progress

    static func progress(
        challenge: WeightChallenge,
        readings: [WeightReading],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Progress {
        let series = dailySeries(readings, calendar: calendar)
        let start = calendar.startOfDay(for: challenge.startDate)
        let endDay = calendar.startOfDay(for: challenge.endDate)
        let today = calendar.startOfDay(for: now)

        // Calendar math
        let totalDays = max(1, (calendar.dateComponents([.day], from: start, to: endDay).day ?? 0))
        let elapsedDays = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let dayNumber = max(1, min(totalDays, elapsedDays + 1))
        let daysLeft = max(0, calendar.dateComponents([.day], from: today, to: endDay).day ?? 0)
        let fractionElapsed = max(0, min(1, Double(elapsedDays) / Double(totalDays)))

        // Your weights
        let inWindow = series.filter { $0.day >= start && $0.day <= endDay }
        let startWeight = challenge.startWeightOverride
            ?? inWindow.first?.pounds
            ?? series.last(where: { $0.day < start })?.pounds
        let latest = inWindow.last ?? (today >= start ? nil : series.last)
        let currentWeight = latest?.pounds
        let trendWeight = latest?.trend

        let lostLbs: Double
        let lostPercent: Double
        if let s = startWeight, let c = currentWeight, s > 0 {
            lostLbs = s - c
            lostPercent = (s - c) / s * 100
        } else {
            lostLbs = 0
            lostPercent = 0
        }

        let expected = challenge.goalLossLbs * fractionElapsed
        let remaining = max(0, challenge.goalLossLbs - lostLbs)
        let requiredDeficit = remaining <= 0 ? 0 : remaining * kcalPerPound / Double(max(1, daysLeft))

        // Least-squares line through the window's weigh-ins, extended to the
        // final day. Fit on raw readings — the smoothed trend lags.
        var projected: Double?
        var weeklyRate: Double?
        if let fit = linearFit(inWindow, calendar: calendar), let s = startWeight, let first = inWindow.first {
            let xEnd = Double(calendar.dateComponents([.day], from: first.day, to: endDay).day ?? 0)
            projected = s - (fit.intercept + fit.slope * xEnd)
            weeklyRate = -fit.slope * 7
        }

        // Friend
        let friend = friendProgress(challenge: challenge)
        let (leader, margin) = compare(
            youLbs: lostLbs, youPct: lostPercent,
            hasYou: startWeight != nil && currentWeight != nil,
            friend: friend, scoring: challenge.scoring
        )

        let weighedInToday = series.last.map { calendar.isDate($0.day, inSameDayAs: today) } ?? false

        return Progress(
            startWeight: startWeight,
            currentWeight: currentWeight,
            trendWeight: trendWeight,
            lostLbs: lostLbs,
            lostPercent: lostPercent,
            dayNumber: dayNumber,
            totalDays: totalDays,
            daysLeft: daysLeft,
            fractionElapsed: fractionElapsed,
            goalLossLbs: challenge.goalLossLbs,
            expectedLossByNow: expected,
            paceDelta: lostLbs - expected,
            projectedLossAtEnd: projected,
            weeklyRate: weeklyRate,
            requiredDailyDeficit: requiredDeficit,
            friend: friend,
            leader: leader,
            margin: margin,
            weighedInToday: weighedInToday,
            weighInStreak: streak(series, today: today, calendar: calendar),
            series: series
        )
    }

    // MARK: - Pieces

    /// Least-squares line through daily weights: lbs = intercept + slope × day,
    /// with day 0 = the first weigh-in. Needs ≥ 3 days.
    static func linearFit(_ days: [DailyWeight], calendar: Calendar = .current) -> (slope: Double, intercept: Double)? {
        guard days.count >= 3, let first = days.first?.day else { return nil }
        let xs = days.map { Double(calendar.dateComponents([.day], from: first, to: $0.day).day ?? 0) }
        let ys = days.map(\.pounds)
        let n = Double(days.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            den += (x - meanX) * (x - meanX)
        }
        guard den > 0 else { return nil }
        let slope = num / den
        return (slope, meanY - slope * meanX)
    }

    // MARK: - Projection to a goal day

    struct Projection: Equatable {
        /// Projected weight on the target day, lbs.
        let weight: Double
        /// Change from your latest weigh-in (negative = loss).
        let change: Double
        /// Trend rate, lbs/week (negative = losing).
        let weeklyRate: Double
        let basedOnDays: Int
    }

    /// Where the last few weeks' trend lands you on `target`. nil with
    /// fewer than three weigh-in days. The rate is clamped to ±3 lb/week so
    /// one noisy week can't project something silly.
    static func projection(
        readings: [WeightReading],
        to target: Date,
        now: Date = Date(),
        lookbackDays: Int = 21,
        calendar: Calendar = .current
    ) -> Projection? {
        let today = calendar.startOfDay(for: now)
        guard let since = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return nil }
        let recent = dailySeries(readings, calendar: calendar).filter { $0.day >= since && $0.day <= today }
        guard let fit = linearFit(recent, calendar: calendar),
              let first = recent.first, let last = recent.last else { return nil }
        let slope = max(-3.0 / 7, min(3.0 / 7, fit.slope))
        let lastX = Double(calendar.dateComponents([.day], from: first.day, to: last.day).day ?? 0)
        let targetX = Double(calendar.dateComponents([.day], from: first.day, to: calendar.startOfDay(for: target)).day ?? 0)
        // Anchor on the fitted value today, then extend with the clamped slope.
        let fittedNow = fit.intercept + fit.slope * lastX
        let projected = fittedNow + slope * max(0, targetX - lastX)
        return Projection(
            weight: projected,
            change: projected - last.pounds,
            weeklyRate: slope * 7,
            basedOnDays: recent.count
        )
    }

    static func friendProgress(challenge: WeightChallenge) -> FriendProgress? {
        let sorted = challenge.friendWeighIns.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }
        guard let start = challenge.friendStartWeight ?? sorted.first?.pounds, start > 0 else { return nil }
        let lost = start - latest.pounds
        return FriendProgress(
            startWeight: start,
            currentWeight: latest.pounds,
            lostLbs: lost,
            lostPercent: lost / start * 100,
            lastWeighIn: latest.date
        )
    }

    static func compare(
        youLbs: Double,
        youPct: Double,
        hasYou: Bool,
        friend: FriendProgress?,
        scoring: WeightChallenge.Scoring
    ) -> (WeightChallengeEngine.Leader, Double) {
        guard hasYou, let friend else { return (.unknown, 0) }
        let you = scoring == .percent ? youPct : youLbs
        let them = scoring == .percent ? friend.lostPercent : friend.lostLbs
        let epsilon = scoring == .percent ? 0.05 : 0.1
        let diff = you - them
        if abs(diff) < epsilon { return (.tied, abs(diff)) }
        return (diff > 0 ? .you : .friend, abs(diff))
    }

    static func streak(_ series: [DailyWeight], today: Date, calendar: Calendar = .current) -> Int {
        let days = Set(series.map(\.day))
        var cursor = today
        // A streak survives until you've missed a full day — today not
        // weighed in yet doesn't break it.
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// Merge readings from several sources. Two readings within ten minutes
    /// of each other within 0.5 lb are the same weigh-in reported twice (a
    /// scale that writes to both Google Health and Apple Health) — keep one.
    static func merge(_ groups: [[WeightReading]]) -> [WeightReading] {
        let all = groups.flatMap { $0 }.sorted { $0.date < $1.date }
        var out: [WeightReading] = []
        for r in all {
            if let last = out.last,
               abs(r.date.timeIntervalSince(last.date)) < 600,
               abs(r.pounds - last.pounds) < 0.5 {
                continue
            }
            out.append(r)
        }
        return out
    }
}
