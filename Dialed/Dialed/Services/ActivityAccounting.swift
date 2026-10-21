//
//  ActivityAccounting.swift
//  Dialed
//
//  What Apple Health already has, so nothing is counted twice. Any app's
//  workout (Apple Watch, Mile A Day, Strava…) and plain walking/running
//  that Health logged as steps and distance are already in your mile and
//  steps. A heart-rate stretch that's mostly that walking isn't a mystery
//  to name; a mixed one (a walk that turned into a pickup game) still is,
//  minus the walking part's calories. Pure Foundation, tested.
//

import Foundation

enum ActivityAccounting {

    /// A Health quantity sample over its own interval (steps, distance in miles).
    struct Sample: Equatable {
        var start: Date
        var end: Date
        var value: Double
    }

    enum Verdict: Equatable {
        /// Nothing in Health explains it: ask what it was.
        case unexplained
        /// Mostly walking/running Health already counted: don't ask.
        case alreadyCounted(miles: Double)
        /// Part walking: still ask, but those minutes' calories are already spoken for.
        case mixed(walkingShare: Double)
    }

    /// Workouts get this much slack each side: people start the app a few
    /// minutes into the walk and stop it a few minutes after.
    static let workoutPadding: TimeInterval = 5 * 60
    /// A minute counts as walking at this cadence or pace.
    static let walkingStepsPerMinute = 90.0
    static let walkingMilesPerMinute = 0.03
    /// Bouts at least this much walking are already counted.
    static let alreadyCountedShare = 0.7
    /// ...or this far, with at least half the minutes walking.
    static let alreadyCountedMiles = 0.25

    /// Workout intervals widened by the padding (any source, any length).
    static func busyIntervals(_ workouts: [DateInterval]) -> [DateInterval] {
        workouts.map { DateInterval(start: $0.start.addingTimeInterval(-workoutPadding),
                                    end: max($0.end, $0.start).addingTimeInterval(workoutPadding)) }
    }

    /// Share of `interval` spanned by any of `busy` (overlaps not double counted).
    static func coveredShare(of interval: DateInterval, by busy: [DateInterval]) -> Double {
        guard interval.duration > 0 else { return 0 }
        let pieces = busy.compactMap { $0.intersection(with: interval) }.sorted { $0.start < $1.start }
        var covered: TimeInterval = 0
        var reach = interval.start
        for p in pieces where p.end > reach {
            covered += p.end.timeIntervalSince(max(p.start, reach))
            reach = p.end
        }
        return min(1, covered / interval.duration)
    }

    static func classify(start: Date, end: Date, steps: [Sample], distance: [Sample]) -> Verdict {
        let minutes = max(1, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
        var walking = 0
        var miles = 0.0
        for m in 0..<minutes {
            let a = start.addingTimeInterval(Double(m) * 60)
            let b = min(end, a.addingTimeInterval(60))
            let length = b.timeIntervalSince(a) / 60
            guard length > 0 else { continue }
            let s = prorated(steps, a, b)
            let d = prorated(distance, a, b)
            miles += d
            if s / length >= walkingStepsPerMinute || d / length >= walkingMilesPerMinute { walking += 1 }
        }
        let share = Double(walking) / Double(minutes)
        if share >= alreadyCountedShare || (miles >= alreadyCountedMiles && share >= 0.5) {
            return .alreadyCounted(miles: miles)
        }
        return share >= 0.15 ? .mixed(walkingShare: share) : .unexplained
    }

    /// Sample totals inside [a, b), each spread evenly over its own interval.
    static func prorated(_ samples: [Sample], _ a: Date, _ b: Date) -> Double {
        samples.reduce(0) { total, s in
            let length = s.end.timeIntervalSince(s.start)
            guard length > 0 else { return total + (s.start >= a && s.start < b ? s.value : 0) }
            let overlap = min(s.end, b).timeIntervalSince(max(s.start, a))
            return overlap > 0 ? total + s.value * overlap / length : total
        }
    }
}
