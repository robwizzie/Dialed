//
//  ActivityReview.swift
//  Dialed
//
//  The numbers behind a heart-rate stretch, for reviewing it before you
//  name it: time in each effort zone, average and peak, the resting and
//  "active" lines it was judged against. Pure Foundation, tested.
//

import Foundation

enum ActivityReview {

    struct Zone: Equatable, Identifiable {
        var name: String
        /// Share of heart-rate reserve where the zone starts.
        var from: Double
        var minutes: Double
        var id: String { name }
    }

    static let zoneEdges: [(name: String, from: Double)] = [("Easy", 0), ("Moderate", 0.4), ("Hard", 0.6), ("Peak", 0.8)]

    /// Resting heart rate the stretch was measured against, recovered from
    /// its average and effort (effort = (avg − rest) / (max − rest)).
    static func resting(average: Double, effort: Double, maxBPM: Double = 185) -> Double {
        guard effort < 0.95 else { return 60 }
        let r = (average - effort * maxBPM) / (1 - effort)
        return min(90, max(40, r))
    }

    /// The bpm that counts as "active" (the detector's line).
    static func activeLine(resting: Double, maxBPM: Double = 185, threshold: Double = 0.4) -> Double {
        resting + max(40, maxBPM - resting) * threshold
    }

    /// Minutes in each zone between `start` and `end`. Each reading counts
    /// until the next one, at most two minutes (gaps aren't invented effort).
    static func zones(_ samples: [ActiveBouts.Sample], from start: Date, to end: Date,
                      resting: Double, maxBPM: Double = 185, gapCap: TimeInterval = 120) -> [Zone] {
        let inside = samples.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
        var minutes = Array(repeating: 0.0, count: zoneEdges.count)
        let reserve = max(40, maxBPM - resting)
        for (i, s) in inside.enumerated() {
            let next = i + 1 < inside.count ? inside[i + 1].date : end
            let seconds = min(gapCap, max(0, next.timeIntervalSince(s.date)))
            let share = (s.bpm - resting) / reserve
            let zone = zoneEdges.lastIndex { share >= $0.from } ?? 0
            minutes[zone] += seconds / 60
        }
        return zoneEdges.enumerated().map { Zone(name: $0.element.name, from: $0.element.from, minutes: minutes[$0.offset]) }
    }

    static func summary(_ samples: [ActiveBouts.Sample], from start: Date, to end: Date) -> (average: Double, peak: Double)? {
        let inside = samples.filter { $0.date >= start && $0.date <= end }.map(\.bpm)
        guard !inside.isEmpty else { return nil }
        return (inside.reduce(0, +) / Double(inside.count), inside.max() ?? 0)
    }
}
