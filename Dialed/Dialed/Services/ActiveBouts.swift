//
//  ActiveBouts.swift
//  Dialed
//
//  Finds the fun stuff your watch didn't call a workout: a stretch of the
//  day where your heart rate stayed well above resting for 10+ minutes
//  (pickleball, a pickup game, yard work, dancing at a wedding). Recorded
//  workouts are left out, short dips (between points, catching your
//  breath) don't break a bout, and each one gets minutes, average / peak
//  heart rate and an estimated calorie burn. Pure Foundation, tested.
//

import Foundation

enum ActiveBouts {

    struct Sample: Equatable {
        var date: Date
        var bpm: Double
    }

    struct Bout: Equatable, Identifiable {
        var start: Date
        var end: Date
        var averageBPM: Double
        var peakBPM: Double
        /// Share of heart-rate reserve, 0–1 (0.4 moderate, 0.6+ hard).
        var effort: Double
        var calories: Double

        var minutes: Double { end.timeIntervalSince(start) / 60 }
        /// Stable across refreshes, for remembering what you called it.
        var id: String { "bout-\(Int(start.timeIntervalSince1970 / 300))" }

        var intensity: String {
            switch effort {
            case ..<0.5:  return "Moderate"
            case ..<0.65: return "Hard"
            default:      return "All out"
            }
        }
    }

    struct Settings {
        var restingBPM: Double?
        var maxBPM: Double = 185
        var weightLbs: Double = 200
        /// Share of heart-rate reserve that counts as "active".
        var threshold = 0.4
        var minimumMinutes = 10.0
        /// A dip this long doesn't end a bout.
        var allowedGapMinutes = 4.0
    }

    /// Resting heart rate when Health doesn't have one: the low end of the
    /// day's readings, kept in a sane range.
    static func estimatedResting(_ samples: [Sample]) -> Double {
        let sorted = samples.map(\.bpm).sorted()
        guard !sorted.isEmpty else { return 62 }
        let low = sorted[Int(Double(sorted.count - 1) * 0.1)]
        return min(85, max(45, low))
    }

    static func find(in raw: [Sample], excluding busy: [DateInterval] = [], settings: Settings = Settings()) -> [Bout] {
        let samples = raw.filter { $0.bpm > 30 && $0.bpm < 230 }.sorted { $0.date < $1.date }
        guard samples.count >= 3 else { return [] }
        let resting = settings.restingBPM ?? estimatedResting(samples)
        let reserve = max(40, settings.maxBPM - resting)
        let line = resting + reserve * settings.threshold
        let gap = settings.allowedGapMinutes * 60

        // Runs of elevated readings, bridging short dips.
        var runs: [[Sample]] = []
        var current: [Sample] = []
        for s in samples where s.bpm >= line {
            if let last = current.last, s.date.timeIntervalSince(last.date) > gap {
                runs.append(current)
                current = []
            }
            current.append(s)
        }
        if !current.isEmpty { runs.append(current) }

        let kg = settings.weightLbs * 0.4536
        return runs.compactMap { run -> Bout? in
            guard let first = run.first, let last = run.last else { return nil }
            let interval = DateInterval(start: first.date, end: last.date)
            guard interval.duration >= settings.minimumMinutes * 60 else { return nil }
            // Mostly elevated inside the window, not a few spikes.
            let inside = samples.filter { interval.contains($0.date) }
            guard Double(run.count) / Double(max(1, inside.count)) >= 0.6 else { return nil }
            // Not a workout you already recorded.
            let overlap = busy.reduce(0.0) { $0 + ($1.intersection(with: interval)?.duration ?? 0) }
            guard overlap < interval.duration * 0.5 else { return nil }

            let average = inside.map(\.bpm).reduce(0, +) / Double(inside.count)
            let effort = min(1, max(0, (average - resting) / reserve))
            // %HRR ≈ %VO2 reserve; METs from an everyday VO2max (~35).
            let mets = 1 + effort * 9
            let calories = mets * 3.5 * kg / 200 * interval.duration / 60
            return Bout(start: first.date, end: last.date, averageBPM: average.rounded(),
                        peakBPM: inside.map(\.bpm).max() ?? average, effort: effort, calories: calories.rounded())
        }
    }

    // MARK: - What was it?

    struct Activity: Hashable {
        let name: String
        let symbol: String
    }

    static let activities: [Activity] = [
        .init(name: "Pickleball", symbol: "figure.pickleball"),
        .init(name: "Basketball", symbol: "figure.basketball"),
        .init(name: "Tennis", symbol: "figure.tennis"),
        .init(name: "Golf", symbol: "figure.golf"),
        .init(name: "Soccer", symbol: "figure.indoor.soccer"),
        .init(name: "Volleyball", symbol: "figure.volleyball"),
        .init(name: "Softball", symbol: "figure.baseball"),
        .init(name: "Hiking", symbol: "figure.hiking"),
        .init(name: "Swimming", symbol: "figure.pool.swim"),
        .init(name: "Dancing", symbol: "figure.dance"),
        .init(name: "Yard work", symbol: "leaf.fill"),
        .init(name: "Playing with kids", symbol: "figure.2.and.child.holdinghands"),
        .init(name: "Skiing", symbol: "figure.skiing.downhill"),
        .init(name: "Kayaking", symbol: "figure.water.fitness"),
        .init(name: "Bowling", symbol: "figure.bowling"),
        .init(name: "Climbing", symbol: "figure.climbing")
    ]

    static func symbol(for name: String) -> String {
        activities.first { $0.name.lowercased() == name.lowercased() }?.symbol ?? "figure.mixed.cardio"
    }

    /// Past labels ranked for this bout: same weekday near the same time
    /// first ("Tuesday-night pickleball"), then most used.
    static func suggestions(for bout: Bout, history: [(name: String, start: Date)], calendar: Calendar = .current) -> [String] {
        let weekday = calendar.component(.weekday, from: bout.start)
        let minute = { (d: Date) in calendar.component(.hour, from: d) * 60 + calendar.component(.minute, from: d) }
        var score: [String: Double] = [:]
        for h in history {
            var s = 1.0
            if calendar.component(.weekday, from: h.start) == weekday { s += 2 }
            if abs(minute(h.start) - minute(bout.start)) <= 90 { s += 2 }
            score[h.name, default: 0] += s
        }
        return score.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }
}
