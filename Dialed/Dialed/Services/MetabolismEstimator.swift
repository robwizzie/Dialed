//
//  MetabolismEstimator.swift
//  Dialed
//
//  How fast your metabolism actually runs, from your own data rather than
//  a formula:
//
//    measured TDEE = average calories eaten + (trend weight lost × 3,500) / days
//    resting rate  = TDEE − average active energy − digestion (10 % of food)
//
//  compared with what Mifflin-St Jeor predicts for your weight, height,
//  age and sex. Fast is ≥ 7 % above the prediction, slow ≥ 7 % below.
//  "Metabolic age" is the age at which the formula would predict the rate
//  you actually have. Pure Foundation, tested.
//

import Foundation

enum MetabolismEstimator {

    enum Sex: String, Codable { case male, female }

    struct Profile: Equatable {
        var age: Double?
        var sex: Sex?
        var heightInches: Double
        var weightLbs: Double
        /// 0–1, from a smart scale.
        var bodyFat: Double?
    }

    struct Day: Equatable {
        var date: Date
        /// Calories eaten (logged or from Health); nil when nothing was logged.
        var eaten: Double?
        /// Apple Health active energy; nil when unknown.
        var active: Double?
    }

    enum Speed: String { case slow = "Slow", average = "Average", fast = "Fast" }
    enum Confidence: String, Comparable {
        case insufficient = "Not enough data", low = "Low", medium = "Medium", high = "High"
        private var rank: Int {
            switch self {
            case .insufficient: return 0
            case .low:          return 1
            case .medium:       return 2
            case .high:         return 3
            }
        }
        static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
    }

    struct Result: Equatable {
        /// Mifflin-St Jeor prediction.
        var predictedBMR: Double?
        /// Katch-McArdle from lean mass, when body fat is known.
        var leanMassBMR: Double?
        var measuredTDEE: Double?
        var measuredRMR: Double?
        var averageEaten: Double?
        var averageActive: Double?
        /// lbs/week by trend over the window (positive = losing).
        var weeklyLoss: Double?
        /// measured RMR / predicted BMR.
        var ratio: Double?
        var speed: Speed?
        var metabolicAge: Double?
        var loggedDays: Int
        var windowDays: Int
        var confidence: Confidence
        /// What's missing or doesn't add up, in plain words.
        var notes: [String]
        var actualAge: Double?

        /// Metabolic age minus your real age (negative = younger).
        var ageDelta: Double? {
            guard let m = metabolicAge, let a = actualAge else { return nil }
            return m - a
        }
    }

    /// A day counts as logged when it has at least this much food.
    static let loggedDayMinimum = 800.0
    static let fastThreshold = 1.07
    static let slowThreshold = 0.93

    // MARK: - Formulas

    static func mifflin(weightLbs: Double, heightInches: Double, age: Double, sex: Sex) -> Double {
        10 * weightLbs * 0.453_592 + 6.25 * heightInches * 2.54 - 5 * age + (sex == .male ? 5 : -161)
    }

    static func katchMcArdle(weightLbs: Double, bodyFat: Double) -> Double {
        370 + 21.6 * weightLbs * 0.453_592 * (1 - bodyFat)
    }

    /// The age at which Mifflin predicts `rmr`, clamped to 18–80.
    static func metabolicAge(rmr: Double, weightLbs: Double, heightInches: Double, sex: Sex) -> Double {
        let raw = (10 * weightLbs * 0.453_592 + 6.25 * heightInches * 2.54 + (sex == .male ? 5 : -161) - rmr) / 5
        return min(80, max(18, raw))
    }

    static func speed(ratio: Double) -> Speed {
        ratio >= fastThreshold ? .fast : ratio <= slowThreshold ? .slow : .average
    }

    // MARK: - Estimate

    /// `days` is the window (oldest first, 14–28 days); `trendStart` and
    /// `trendEnd` are trend weights at its first and last day.
    static func estimate(profile: Profile, days: [Day], trendStart: Double?, trendEnd: Double?) -> Result {
        var notes: [String] = []
        var predicted: Double?
        if let age = profile.age, let sex = profile.sex {
            predicted = mifflin(weightLbs: profile.weightLbs, heightInches: profile.heightInches, age: age, sex: sex)
        } else {
            notes.append("Add your birth date and sex (Settings → Profile, or Apple Health) to compare with your age.")
        }
        let lean = profile.bodyFat.map { katchMcArdle(weightLbs: profile.weightLbs, bodyFat: $0) }

        let logged = days.filter { ($0.eaten ?? 0) >= loggedDayMinimum }
        var span = 0
        if let first = days.first, let last = days.last {
            span = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        }
        let windowDays = max(1, span)
        var result = Result(predictedBMR: predicted, leanMassBMR: lean, measuredTDEE: nil, measuredRMR: nil,
                            averageEaten: nil, averageActive: nil, weeklyLoss: nil, ratio: nil, speed: nil,
                            metabolicAge: nil, loggedDays: logged.count, windowDays: windowDays,
                            confidence: .insufficient, notes: notes, actualAge: profile.age)

        guard logged.count >= 10 else {
            result.notes.append("Log everything you eat for \(10 - logged.count) more day\(10 - logged.count == 1 ? "" : "s") (10 needed over the last 2–4 weeks).")
            return result
        }
        guard let start = trendStart, let end = trendEnd, windowDays >= 10 else {
            result.notes.append("Weigh in most mornings for two weeks so the trend can show your real rate.")
            return result
        }

        let eaten = logged.reduce(0) { $0 + ($1.eaten ?? 0) } / Double(logged.count)
        let lostPerDay = (start - end) / Double(windowDays)
        let tdee = eaten + lostPerDay * 3_500
        let activeDays = logged.compactMap(\.active)
        let active = activeDays.isEmpty ? nil : activeDays.reduce(0, +) / Double(activeDays.count)
        // Without Health's active energy, assume a light-activity day (≈ 25 % of TDEE).
        let rmr = tdee - (active ?? tdee * 0.25) - eaten * 0.10

        result.averageEaten = eaten.rounded()
        result.averageActive = active?.rounded()
        result.measuredTDEE = tdee.rounded()
        result.measuredRMR = rmr.rounded()
        result.weeklyLoss = lostPerDay * 7

        var confidence: Confidence = logged.count >= 21 ? .high : logged.count >= 14 ? .medium : .low
        if active == nil {
            confidence = min(confidence, .low)
            result.notes.append("No active energy from Apple Health, so movement is estimated.")
        }
        let completeness = Double(logged.count) / Double(max(1, days.count))
        if completeness < 0.7 { confidence = min(confidence, .medium) }

        if let predicted, let sex = profile.sex {
            let ratio = rmr / predicted
            // Real resting rates sit within ~±20 % of the formula; further off
            // usually means missed meals in the log or water swings, not a broken metabolism.
            if ratio < 0.7 || ratio > 1.35 {
                result.notes.append("Your numbers don't add up yet. Usually a few meals are missing from the log; keep logging everything and it settles.")
                result.confidence = .low
                return result
            }
            result.ratio = ratio
            result.speed = speed(ratio: ratio)
            result.metabolicAge = metabolicAge(rmr: rmr, weightLbs: profile.weightLbs,
                                               heightInches: profile.heightInches, sex: sex).rounded()
        }
        result.confidence = confidence
        return result
    }

    /// One plain sentence for the verdict.
    static func summary(_ r: Result) -> String {
        guard let speed = r.speed, let ratio = r.ratio else {
            return "Keep logging food and weighing in. Your real burn shows up after about two weeks."
        }
        let pct = Int(((ratio - 1) * 100).rounded())
        switch speed {
        case .fast:    return "You burn about \(pct)% more at rest than the formula predicts for you. Your engine runs hot."
        case .slow:    return "You burn about \(-pct)% less at rest than predicted. Common during a long cut; strength work and protein help."
        case .average: return "Your resting burn is within \(abs(pct))% of the prediction for your age and size: right on average."
        }
    }
}
