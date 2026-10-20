//
//  ProteinPacing.swift
//  Dialed
//
//  "You're at 60 g by 3 PM — a protein shake now keeps you on track."
//  Learns when you usually eat your protein (the share of a day's total
//  you've had by each hour, averaged over recent days), so a late-lunch
//  person isn't nagged at noon. Compares today against it, sizes a snack
//  to the gap from the food table, and says whether it's worth a nudge.
//  Pure Foundation, tested.
//

import Foundation

enum ProteinPacing {

    struct Meal: Equatable {
        var date: Date
        var protein: Double
    }

    // MARK: - Curve

    /// Share of a day's protein eaten by the end of each hour: 25 values,
    /// hour 0 … 24, rising to 1.
    struct Curve: Equatable {
        var shares: [Double]
        /// From your own days (vs the default).
        var learned: Bool

        func share(at date: Date, calendar: Calendar = .current) -> Double {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            let h = c.hour ?? 0
            let f = Double(c.minute ?? 0) / 60
            let a = shares[max(0, min(24, h))]
            let b = shares[max(0, min(24, h + 1))]
            return a + (b - a) * f
        }
    }

    /// Breakfast ~8, lunch ~12:30, a snack ~3:30, dinner ~7.
    static let defaultCurve: Curve = {
        let points: [(Double, Double)] = [(0, 0), (7, 0), (9, 0.22), (12, 0.25), (13.5, 0.5), (15, 0.52),
                                          (16, 0.62), (18, 0.65), (20, 0.95), (22, 1), (24, 1)]
        let shares = (0...24).map { h -> Double in
            let x = Double(h)
            guard let i = points.firstIndex(where: { $0.0 >= x }) else { return 1 }
            if i == 0 { return points[0].1 }
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        }
        return Curve(shares: shares, learned: false)
    }()

    /// Your curve from the last `days` before today (days with at least
    /// 40 g count). Needs five such days; until then the default.
    static func learn(_ meals: [Meal], now: Date = Date(), days: Int = 21, calendar: Calendar = .current) -> Curve {
        let today = calendar.startOfDay(for: now)
        guard let since = calendar.date(byAdding: .day, value: -days, to: today) else { return defaultCurve }
        let byDay = Dictionary(grouping: meals.filter { $0.date >= since && $0.date < today && $0.protein > 0 }) {
            calendar.startOfDay(for: $0.date)
        }
        var sums = [Double](repeating: 0, count: 25)
        var count = 0
        for (_, dayMeals) in byDay {
            let total = dayMeals.reduce(0) { $0 + $1.protein }
            guard total >= 40 else { continue }
            count += 1
            for h in 0...24 {
                // Eaten before the end of hour h (h = 24: the whole day).
                let eaten = dayMeals.filter { calendar.component(.hour, from: $0.date) < h }.reduce(0) { $0 + $1.protein }
                sums[h] += eaten / total
            }
        }
        guard count >= 5 else { return defaultCurve }
        // A little of the default keeps one odd day from skewing it.
        var shares = sums.enumerated().map { 0.8 * $0.element / Double(count) + 0.2 * defaultCurve.shares[$0.offset] }
        for h in 1...24 { shares[h] = max(shares[h], shares[h - 1]) }
        shares[24] = 1
        return Curve(shares: shares, learned: true)
    }

    // MARK: - Snacks sized to the gap

    struct Option: Equatable {
        /// What it's logged as ("Chicken breast, 4 oz").
        var name: String
        /// How it reads in a sentence ("4 oz of chicken").
        var phrase: String
        var protein: Double
        var calories: Double
        var carbs: Double
        var fat: Double
    }

    /// Common protein fixes priced from the food table, smallest first.
    static let options: [Option] = {
        let picks: [(String, String, String, Double, String)] = [
            ("Greek yogurt", "a Greek yogurt", "Greek yogurt", 1, "piece"),
            ("Protein bar", "a protein bar", "Protein bar", 1, "piece"),
            ("Protein shake", "a protein shake", "Whey protein", 1, "scoop"),
            ("Cottage cheese, 1 cup", "a cup of cottage cheese", "Cottage cheese", 1, "cup"),
            ("Egg whites, 1 cup", "a cup of egg whites", "Egg whites", 1, "cup"),
            ("Chicken breast, 4 oz", "4 oz of chicken", "Chicken breast", 4, "oz"),
            ("Tuna, 1 can", "a can of tuna", "Tuna (canned)", 1, "can")
        ]
        return picks.compactMap { label, phrase, food, amount, unit -> Option? in
            guard let f = NutritionTable.foods.first(where: { $0.name == food }),
                  let g = f.grams(amount, unit) else { return nil }
            let k = g / 100
            return Option(name: label, phrase: phrase, protein: (f.protein * k).rounded(), calories: (f.calories * k).rounded(),
                          carbs: (f.carbs * k).rounded(), fat: (f.fat * k).rounded())
        }
        .sorted { $0.protein < $1.protein }
    }()

    /// A shake for the usual 15–40 g gap (the easy fix), a yogurt for
    /// less, chicken or tuna for more.
    static func suggestion(for gap: Double) -> Option? {
        guard gap >= 10 else { return nil }
        if (15...40).contains(gap), let shake = options.first(where: { $0.name == "Protein shake" }) { return shake }
        return options.first { $0.protein >= gap * 0.85 } ?? options.last
    }

    // MARK: - Today

    struct Status: Equatable {
        var actual: Double
        var expected: Double
        var target: Double
        /// expected − actual (positive = behind).
        var gap: Double { expected - actual }
        var suggestion: Option?
        var shouldNudge: Bool
        var message: String
    }

    static func status(actual: Double, target: Double, curve: Curve, now: Date = Date(),
                       lastMealAt: Date? = nil, calendar: Calendar = .current) -> Status {
        let expected = target * curve.share(at: now, calendar: calendar)
        let gap = expected - actual
        let hour = calendar.component(.hour, from: now)
        let suggestion = suggestion(for: gap)
        let recentMeal = lastMealAt.map { now.timeIntervalSince($0) < 90 * 60 && $0 <= now } ?? false
        let shouldNudge = gap >= 20 && (11..<20).contains(hour) && !recentMeal && actual < target
        let time = clock(now, calendar: calendar)

        let message: String
        if actual >= target {
            message = "\(Int(actual)) g. Protein goal done for today."
        } else if gap < 10 {
            message = "\(Int(actual)) g by \(time). Right on pace for \(Int(target)) g."
        } else if let s = suggestion {
            message = "You're at \(Int(actual)) g by \(time). \(s.phrase.prefix(1).uppercased() + s.phrase.dropFirst()) (\(Int(s.protein)) g) now keeps you on track."
        } else {
            message = "\(Int(actual)) g by \(time), about \(Int(gap)) g behind pace."
        }
        return Status(actual: actual, expected: expected, target: target, suggestion: suggestion,
                      shouldNudge: shouldNudge, message: message)
    }

    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        return (m == 0 ? "\(h12)" : "\(h12):\(String(format: "%02d", m))") + (h < 12 ? " AM" : " PM")
    }
}
