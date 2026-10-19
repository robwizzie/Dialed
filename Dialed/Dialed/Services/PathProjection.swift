//
//  PathProjection.swift
//  Dialed
//
//  "If every day were like…": takes your last week of real days (calories
//  eaten, calories burned) and shows where each kind of day would put your
//  weight on your goal day. Uses the usual ~3,500 kcal per pound, so it's
//  a direction-and-size estimate, not a promise. Pure Foundation, tested.
//

import Foundation

enum PathProjection {

    /// One finished day of data.
    struct DayRecord: Equatable {
        let date: Date
        let caloriesIn: Double
        /// Active calories from the watch/Apple Health, if any.
        let activeKcal: Double?
        let steps: Int
    }

    struct Scenario: Identifiable, Equatable {
        enum Kind: String { case yesterday, best, typical, toughest, plan }
        let kind: Kind
        let title: String
        /// e.g. "Fri, Oct 17 · 2,950 eaten · 3,300 burned"
        let detail: String
        /// Calories in minus calories out (negative = deficit).
        let dailyNet: Double
        /// Change in pounds by the goal day.
        let poundsChange: Double
        let projectedWeight: Double

        var id: String { kind.rawValue }
        var losing: Bool { poundsChange < 0 }
    }

    static let kcalPerPound = 3_500.0
    /// Below this the day probably wasn't fully logged.
    static let minLoggedCalories = 1_000.0

    /// Calories out for a day: resting + everyday movement scaled to body
    /// weight, plus what the watch measured (or a step estimate without it).
    static func caloriesOut(weight: Double, activeKcal: Double?, steps: Int) -> Double {
        let base = weight * 12
        if let active = activeKcal, active > 0 { return base + active }
        // ~0.04 kcal per step at 150 lb, scaled by weight.
        return base + Double(steps) * 0.04 * (weight / 150)
    }

    static func scenarios(
        days: [DayRecord],
        weight: Double,
        calorieTarget: Double,
        goalDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Scenario] {
        let today = calendar.startOfDay(for: now)
        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: goalDate)).day ?? 1)

        // Finished, fully-logged days from the last week.
        let logged = days
            .filter { $0.date < today && $0.caloriesIn >= minLoggedCalories }
            .sorted { $0.date < $1.date }
            .suffix(7)

        func net(_ d: DayRecord) -> Double {
            d.caloriesIn - caloriesOut(weight: weight, activeKcal: d.activeKcal, steps: d.steps)
        }
        func make(_ kind: Scenario.Kind, _ title: String, _ detail: String, _ dailyNet: Double) -> Scenario {
            let change = dailyNet * Double(daysLeft) / kcalPerPound
            return Scenario(kind: kind, title: title, detail: detail, dailyNet: dailyNet,
                            poundsChange: change, projectedWeight: weight + change)
        }
        func describe(_ d: DayRecord) -> String {
            let day = d.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let out = caloriesOut(weight: weight, activeKcal: d.activeKcal, steps: d.steps)
            return "\(day) · \(Int(d.caloriesIn).formatted()) eaten · \(Int(out).formatted()) burned"
        }

        var result: [Scenario] = []

        // Yesterday, if it's in the logged set.
        if let last = logged.last,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(last.date, inSameDayAs: yesterday) {
            result.append(make(.yesterday, "Like yesterday", describe(last), net(last)))
        }

        if logged.count >= 2 {
            let byNet = logged.sorted { net($0) < net($1) }
            let best = byNet.first!
            let worst = byNet.last!
            let nets = byNet.map(net)
            let median = nets.count % 2 == 1
                ? nets[nets.count / 2]
                : (nets[nets.count / 2 - 1] + nets[nets.count / 2]) / 2
            result.append(make(.best, "Like your best day", describe(best), net(best)))
            result.append(make(.typical, "Like your typical day",
                               "Middle of your last \(logged.count) logged days", median))
            if net(worst) > net(best) {
                result.append(make(.toughest, "Like your toughest day", describe(worst), net(worst)))
            }
        }

        // Always show what hitting the plan's budget does on a typical day
        // of movement.
        let typicalOut: Double
        if logged.isEmpty {
            typicalOut = caloriesOut(weight: weight, activeKcal: nil, steps: 8_000)
        } else {
            let outs = logged.map { caloriesOut(weight: weight, activeKcal: $0.activeKcal, steps: $0.steps) }
            typicalOut = outs.reduce(0, +) / Double(outs.count)
        }
        if calorieTarget > 0 {
            result.append(make(.plan, "If you hit your budget",
                               "\(Int(calorieTarget).formatted()) eaten · \(Int(typicalOut).formatted()) burned",
                               calorieTarget - typicalOut))
        }
        return result
    }
}
