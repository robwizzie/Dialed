//
//  StrengthProgression.swift
//  Dialed
//
//  Pure logic behind the workout logger: reads plan prescriptions
//  ("4 × 8", "3 × 10 / leg", "45 s"), suggests the next working weight
//  from the last logged session (double progression: hit every set →
//  add weight, miss → repeat, fall apart → back off 5 %), and scores
//  sessions by estimated 1-rep max (Epley) for the strength-vs-weight
//  screen. No SwiftData, no UIKit — fully unit-tested.
//

import Foundation

enum StrengthProgression {

    // MARK: - Prescriptions

    enum Prescription: Equatable {
        /// `sets` × `reps` (per leg / arm / side when `perSide`).
        case setsReps(sets: Int, reps: Int, perSide: Bool)
        /// Work for a fixed time ("45 s", "15 min").
        case duration(seconds: Int)

        var sets: Int? {
            if case let .setsReps(sets, _, _) = self { return sets }
            return nil
        }

        var reps: Int? {
            if case let .setsReps(_, reps, _) = self { return reps }
            return nil
        }
    }

    /// Reads the plan's prescription strings. Returns nil for anything
    /// that isn't sets × reps or a single duration (e.g. "× 6–8",
    /// "8 rounds · 30 s hard / 90 s easy", "45–60 min").
    static func parse(_ text: String) -> Prescription? {
        let s = text.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if s.contains("x") {
            let parts = s.split(separator: "x", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2,
                  let sets = Int(parts[0]), sets > 0,
                  let reps = leadingInt(parts[1]), reps > 0 else { return nil }
            let rest = parts[1]
            let perSide = rest.contains("/") || rest.contains("each") || rest.contains("per")
            return .setsReps(sets: sets, reps: reps, perSide: perSide)
        }

        // Single durations only: "45 s", "5 min", "15 min".
        guard !s.contains("–"), !s.contains("-"), !s.contains("·"),
              let n = leadingInt(s), n > 0 else { return nil }
        let unit = s.drop(while: { $0.isNumber || $0 == " " })
        if unit.hasPrefix("min") { return .duration(seconds: n * 60) }
        if unit.hasPrefix("s") { return .duration(seconds: n) }
        return nil
    }

    private static func leadingInt(_ s: String) -> Int? {
        Int(String(s.prefix(while: { $0.isNumber })))
    }

    // MARK: - Equipment

    enum Equipment: Equatable {
        /// Barbell squat / deadlift / RDL — big lower-body lifts, +10 lb.
        case barbellLower
        case barbell
        case dumbbell
        case cable
        /// Push-ups, planks, mountain climbers: no weight to suggest.
        case bodyweight

        /// Weight added after a clean session.
        var increment: Double { self == .barbellLower ? 10 : 5 }
        /// Plates / dumbbell rack / cable stack all move in 5 lb steps.
        var step: Double { 5 }
    }

    static func equipment(for name: String) -> Equipment {
        let n = name.lowercased()
        if n.contains("cable") { return .cable }
        if n.contains("push-up") || n.contains("plank") || n.contains("mountain climber") {
            return .bodyweight
        }
        if n.contains("barbell") || n == "bench press" || n.hasPrefix("bench press") {
            let lower = n.contains("squat") || n.contains("deadlift") || n.contains("rdl")
            return lower ? .barbellLower : .barbell
        }
        if n.contains("dumbbell") || n.contains("kettlebell") || n.contains("goblet") || n.contains("rdl") {
            return .dumbbell
        }
        return .dumbbell
    }

    static func round(_ pounds: Double, step: Double = 5) -> Double {
        guard step > 0 else { return pounds }
        return (pounds / step).rounded() * step
    }

    // MARK: - Suggestions

    struct LoggedSet: Equatable {
        let weight: Double
        let reps: Int
        let completed: Bool

        init(weight: Double, reps: Int, completed: Bool = true) {
            self.weight = weight
            self.reps = reps
            self.completed = completed
        }
    }

    struct Suggestion: Equatable {
        enum Kind: Equatable { case increase, repeatWeight, deload }
        let weight: Double
        let kind: Kind

        var reason: String {
            switch kind {
            case .increase:     return "Hit every set last time — go up."
            case .repeatWeight: return "Same weight — own every rep this time."
            case .deload:       return "Tough last time — back off 5% and rebuild."
            }
        }
    }

    static let firstTimeHint = "Pick a weight where the last 2 reps are hard."

    /// Next working weight for `exerciseName`, from that exercise's last
    /// logged session. Nil the first time (or for bodyweight / timed work).
    static func suggest(
        exerciseName: String,
        prescription: Prescription?,
        lastSession: [LoggedSet]
    ) -> Suggestion? {
        let equipment = equipment(for: exerciseName)
        guard equipment != .bodyweight,
              case let .setsReps(targetSets, targetReps, _)? = prescription else { return nil }

        let working = lastSession.filter { $0.completed && $0.weight > 0 && $0.reps > 0 }
        guard let top = working.map(\.weight).max() else { return nil }
        let atTop = working.filter { $0.weight == top }

        let hits = atTop.filter { $0.reps >= targetReps }.count
        let repsDone = atTop.reduce(0) { $0 + min($1.reps, targetReps) }
        let repsWanted = targetSets * targetReps

        if hits >= targetSets {
            return Suggestion(weight: round(top + equipment.increment, step: equipment.step), kind: .increase)
        }
        // "Failed badly": under 70 % of the prescribed reps at that weight.
        if Double(repsDone) < 0.7 * Double(repsWanted) {
            let lighter = round(top * 0.95, step: equipment.step)
            let weight = max(equipment.step, min(lighter, top - equipment.step))
            return Suggestion(weight: weight, kind: .deload)
        }
        return Suggestion(weight: top, kind: .repeatWeight)
    }

    // MARK: - Estimated 1RM

    /// Epley: w × (1 + reps / 30). One rep is the weight itself.
    static func epley(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Best e1RM among the completed sets of one session.
    static func bestE1RM(_ sets: [LoggedSet]) -> Double {
        sets.filter(\.completed).map { epley(weight: $0.weight, reps: $0.reps) }.max() ?? 0
    }

    struct SessionPoint: Equatable {
        let date: Date
        let e1RM: Double
    }

    /// One point per session (sessions with no weighted completed sets
    /// are skipped), oldest first.
    static func e1RMSeries(_ sessions: [(date: Date, sets: [LoggedSet])]) -> [SessionPoint] {
        sessions
            .map { SessionPoint(date: $0.date, e1RM: bestE1RM($0.sets)) }
            .filter { $0.e1RM > 0 }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Main lifts

    enum MainLift: String, CaseIterable, Identifiable {
        case squat, bench, rdl, latPulldown, shoulderPress, row

        var id: String { rawValue }

        var title: String {
            switch self {
            case .squat:         return "Squat"
            case .bench:         return "Bench"
            case .rdl:           return "RDL"
            case .latPulldown:   return "Lat pulldown"
            case .shoulderPress: return "Shoulder press"
            case .row:           return "Row"
            }
        }

        /// Whether a logged exercise name counts toward this lift.
        func matches(_ exerciseName: String) -> Bool {
            let n = exerciseName.lowercased()
            switch self {
            case .squat:         return n.contains("back squat")
            case .bench:         return n.contains("bench press")
            case .rdl:           return n.contains("romanian deadlift") && n.contains("barbell")
            case .latPulldown:   return n.contains("lat pulldown")
            case .shoulderPress: return n.contains("shoulder press")
            case .row:           return n.contains("row") && n.contains("dumbbell")
            }
        }
    }

    // MARK: - Headline

    static func signed(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded > 0 { return "+\(rounded)" }
        if rounded < 0 { return "−\(abs(rounded))" }
        return "±0"
    }

    /// "Bench e1RM +10 lb while you're −6 lb".
    static func headline(lift: String, e1RMChange: Double, weightChange: Double?) -> String {
        let liftPart = "\(lift) e1RM \(signed(e1RMChange)) lb"
        guard let w = weightChange else { return liftPart }
        return "\(liftPart) while you're \(signed(w)) lb"
    }
}
