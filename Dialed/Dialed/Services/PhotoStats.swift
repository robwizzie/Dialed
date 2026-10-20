//
//  PhotoStats.swift
//  Dialed
//
//  What your body measured around each progress photo: trend weight, the
//  scale's reading and body fat % — and how two photos differ ("−8.4 lb
//  trend · −2.1% body fat · 6 weeks"). Pure Foundation, tested; the
//  readings come from PhotoStatsLoader.
//

import Foundation

enum PhotoStats {

    /// A body-fat reading as a fraction (0.322 = 32.2 %).
    struct Reading: Equatable {
        var date: Date
        var value: Double
    }

    struct Stats: Equatable {
        var trend: Double?
        var scale: Double?
        /// Fraction, 0–1.
        var bodyFat: Double?

        var isEmpty: Bool { trend == nil && scale == nil && bodyFat == nil }
    }

    struct Delta: Equatable {
        var trend: Double?
        var scale: Double?
        /// Percentage points (−2.1 = 2.1 points lower).
        var bodyFatPoints: Double?
        var days: Int

        /// "−8.4 lb trend · −2.1% body fat · 6 weeks"
        var summary: String {
            var parts: [String] = []
            if let t = trend { parts.append("\(PhotoStats.signed(t)) lb trend") }
            else if let s = scale { parts.append("\(PhotoStats.signed(s)) lb") }
            if let f = bodyFatPoints { parts.append("\(PhotoStats.signed(f))% body fat") }
            parts.append(PhotoStats.span(days))
            return parts.joined(separator: " · ")
        }
    }

    /// Trend: the last trend day on or before the photo (up to two weeks
    /// back), else the first within three days after. Scale: the weight
    /// saved with the photo, else that day's weigh-in. Body fat: the
    /// reading nearest the photo within three days.
    static func stats(on date: Date, photoWeight: Double?, series: [WeightChallengeEngine.DailyWeight],
                      bodyFat: [Reading], calendar: Calendar = .current) -> Stats {
        let day = calendar.startOfDay(for: date)
        func days(_ a: Date, _ b: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
        }
        let before = series.last { $0.day <= day && days($0.day, day) <= 14 }
        let after = series.first { $0.day > day && days(day, $0.day) <= 3 }
        let trend = (before ?? after)?.trend
        let scale = photoWeight ?? series.first { calendar.isDate($0.day, inSameDayAs: day) }?.pounds
        let fat = bodyFat
            .filter { abs(days($0.date, date)) <= 3 }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
            .value
        return Stats(trend: trend, scale: scale, bodyFat: fat)
    }

    static func delta(from a: Stats, at dateA: Date, to b: Stats, at dateB: Date, calendar: Calendar = .current) -> Delta {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: dateA),
                                           to: calendar.startOfDay(for: dateB)).day ?? 0
        func diff(_ x: Double?, _ y: Double?) -> Double? {
            guard let x, let y else { return nil }
            return y - x
        }
        return Delta(trend: diff(a.trend, b.trend), scale: diff(a.scale, b.scale),
                     bodyFatPoints: diff(a.bodyFat, b.bodyFat).map { $0 * 100 }, days: abs(days))
    }

    // MARK: - Formatting

    /// −8.4 / +1.2 / ±0.0 (one decimal, real minus sign).
    static func signed(_ value: Double) -> String {
        let r = (value * 10).rounded() / 10
        if r > 0 { return "+" + String(format: "%.1f", r) }
        if r < 0 { return "−" + String(format: "%.1f", -r) }
        return "±0.0"
    }

    /// "6 weeks", "1 week", "5 days", "same day"
    static func span(_ days: Int) -> String {
        let d = abs(days)
        if d == 0 { return "same day" }
        if d >= 14 { return "\(d / 7) weeks" }
        if d >= 7 { return "1 week" + (d > 7 ? " \(d - 7) day\(d - 7 == 1 ? "" : "s")" : "") }
        return "\(d) day\(d == 1 ? "" : "s")"
    }

    /// "206.1" / "32.2%"
    static func pounds(_ v: Double) -> String { String(format: "%.1f", v) }
    static func percent(_ fraction: Double) -> String { String(format: "%.1f%%", fraction * 100) }
}
