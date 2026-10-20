//
//  StrengthMilestones.swift
//  Dialed
//
//  Personal records and the next round number to chase. From every
//  finished set: each exercise's best estimated max (Epley, reps capped at
//  12 so a set of 20 doesn't inflate it), heaviest weight, and the PRs a
//  just-finished session set: heaviest ever, best estimated max, or more
//  reps at a weight than ever before. Then the next milestone: plate
//  numbers for barbell lifts ("185 bench", "two plates" at 225), the next
//  10 lb (5 lb for dumbbells) for everything else. Pure Foundation, tested.
//

import Foundation

enum StrengthMilestones {

    /// One finished set.
    struct SetRecord: Equatable {
        var exercise: String
        var date: Date
        var weight: Double
        var reps: Int
    }

    /// Estimated one-rep max with reps capped at 12.
    static func e1RM(weight: Double, reps: Int) -> Double {
        StrengthProgression.epley(weight: weight, reps: min(reps, 12))
    }

    // MARK: - Bests

    struct Best: Equatable {
        var exercise: String
        var e1RM: Double
        /// The set behind the best estimated max.
        var e1RMSet: SetRecord
        var heaviest: SetRecord
    }

    /// Best estimated max and heaviest set per exercise (weighted sets only).
    static func bests(_ sets: [SetRecord]) -> [String: Best] {
        var out: [String: Best] = [:]
        for s in sets where s.weight > 0 && s.reps > 0 {
            let e = e1RM(weight: s.weight, reps: s.reps)
            guard var b = out[s.exercise] else {
                out[s.exercise] = Best(exercise: s.exercise, e1RM: e, e1RMSet: s, heaviest: s)
                continue
            }
            if e > b.e1RM { b.e1RM = e; b.e1RMSet = s }
            if s.weight > b.heaviest.weight || (s.weight == b.heaviest.weight && s.reps > b.heaviest.reps) { b.heaviest = s }
            out[s.exercise] = b
        }
        return out
    }

    // MARK: - PRs

    struct PR: Equatable {
        enum Kind: Equatable { case heaviest, estimatedMax, repsAtWeight }

        var exercise: String
        var kind: Kind
        var weight: Double
        var reps: Int
        var e1RM: Double
        /// The record it beat (weight, estimated max, or reps).
        var previous: Double

        /// "Bench press: heaviest ever, 155 × 8 (was 145)"
        var text: String {
            let set = "\(formatPounds(weight)) × \(reps)"
            switch kind {
            case .heaviest:
                return "\(exercise): heaviest ever, \(set) (was \(formatPounds(previous)))"
            case .estimatedMax:
                return "\(exercise): new est. max \(formatPounds(e1RM.rounded())) lb from \(set) (was \(formatPounds(previous.rounded())))"
            case .repsAtWeight:
                return "\(exercise): most reps at \(formatPounds(weight)) lb, \(reps) (was \(Int(previous)))"
            }
        }
    }

    /// Records set in `session`, at most one per exercise (heaviest beats
    /// reps at a weight beats estimated max). Exercises with no history don't count:
    /// a first log isn't a record yet.
    static func prs(session: [SetRecord], history: [SetRecord]) -> [PR] {
        let past = bests(history)
        var out: [PR] = []
        var seen: [String] = []
        for s in session where !seen.contains(s.exercise) { seen.append(s.exercise) }
        for name in seen {
            guard let before = past[name] else { continue }
            let mine = session.filter { $0.exercise == name && $0.weight > 0 && $0.reps > 0 }
            guard let now = bests(mine)[name] else { continue }

            if now.heaviest.weight > before.heaviest.weight {
                out.append(PR(exercise: name, kind: .heaviest, weight: now.heaviest.weight, reps: now.heaviest.reps,
                              e1RM: now.e1RM, previous: before.heaviest.weight))
                continue
            }
            // More reps at a weight you've done before.
            let pastForName = history.filter { $0.exercise == name }
            let best = mine
                .compactMap { s -> (SetRecord, Int)? in
                    let prior = pastForName.filter { $0.weight == s.weight }.map(\.reps).max()
                    return prior.flatMap { s.reps > $0 ? (s, $0) : nil }
                }
                .max { $0.0.weight < $1.0.weight }
            if let (s, prior) = best {
                out.append(PR(exercise: name, kind: .repsAtWeight, weight: s.weight, reps: s.reps,
                              e1RM: e1RM(weight: s.weight, reps: s.reps), previous: Double(prior)))
                continue
            }
            // A weight × reps you've never done that estimates higher.
            if now.e1RM >= before.e1RM + 1 {
                out.append(PR(exercise: name, kind: .estimatedMax, weight: now.e1RMSet.weight, reps: now.e1RMSet.reps,
                              e1RM: now.e1RM, previous: before.e1RM))
            }
        }
        return out
    }

    // MARK: - Next milestone

    struct Milestone: Equatable {
        var exercise: String
        var target: Double
        /// "185 bench press", "two plates (225) on squat"
        var label: String
        /// lbs between your heaviest set and the target.
        var remaining: Double
        /// Your estimated max clears it by 5%: go try a single (barbell
        /// lifts only; a machine's 12-rep estimate isn't a single).
        var withinReach: Bool

        /// "You're 5 lb from a 185 bench press"
        var text: String {
            if withinReach { return "Your est. max says \(label) is already in you. Try a single." }
            return "You're \(formatPounds(remaining)) lb from \(label)"
        }
    }

    /// Plate numbers worth celebrating on a barbell.
    static let plateTargets: [(Double, String?)] = [
        (95, nil), (135, "one plate"), (155, nil), (185, nil), (225, "two plates"), (275, nil),
        (315, "three plates"), (365, nil), (405, "four plates"), (455, nil), (495, "five plates")
    ]

    static func isPlateLift(_ name: String) -> Bool {
        let n = name.lowercased()
        if ["dumbbell", "goblet", "kettlebell", "cable", "machine", "db "].contains(where: n.contains) { return false }
        return ["bench press", "squat", "deadlift", "barbell", "overhead press"].contains(where: n.contains)
    }

    static func nextMilestone(for best: Best) -> Milestone? {
        let heaviest = best.heaviest.weight
        guard heaviest > 0 else { return nil }
        let name = best.exercise.lowercased()
        let target: Double
        var label: String
        if isPlateLift(best.exercise), let t = plateTargets.first(where: { $0.0 > heaviest }) {
            target = t.0
            label = t.1.map { "\($0) (\(formatPounds(target))) on \(name)" } ?? "a \(formatPounds(target)) \(name)"
        } else {
            let step: Double = StrengthProgression.equipment(for: best.exercise) == .dumbbell ? 5 : 10
            target = (heaviest / step).rounded(.down) * step + step
            label = "a \(formatPounds(target)) \(name)"
        }
        return Milestone(exercise: best.exercise, target: target, label: label, remaining: target - heaviest,
                         withinReach: isPlateLift(best.exercise) && best.e1RM >= target * 1.05)
    }
}
