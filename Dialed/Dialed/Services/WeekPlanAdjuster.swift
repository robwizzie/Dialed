//
//  WeekPlanAdjuster.swift
//  Dialed
//
//  Keeps the week sensible when you train something other than the plan.
//  If what you logged today looks more like a later day this week (you
//  did Strength B on a Strength A day, or lifted on a bike day), the two
//  days swap — so you don't repeat the same muscles tomorrow and nothing
//  gets skipped. Pure Foundation, tested.
//

import Foundation

enum WeekPlanAdjuster {
    enum Focus: String, CaseIterable { case push, pull, legs, hinge, core, cardio }

    /// What an exercise mostly trains, from its name.
    static func focus(of exercise: String) -> Set<Focus> {
        let n = exercise.lowercased()
        var out: Set<Focus> = []
        if ["bench", "press", "incline", "push-up", "pushup", "fly", "dip", "pushdown", "tricep", "thruster"].contains(where: n.contains) { out.insert(.push) }
        if ["row", "pulldown", "pull-up", "pullup", "chin", "face pull", "curl", "lat"].contains(where: n.contains) { out.insert(.pull) }
        if ["squat", "lunge", "leg press", "step-up", "thruster", "leg ext"].contains(where: n.contains) { out.insert(.legs) }
        if ["deadlift", "rdl", "hinge", "swing", "hip thrust", "good morning", "hamstring"].contains(where: n.contains) { out.insert(.hinge) }
        if ["plank", "woodchop", "crunch", "ab", "core", "mountain climber", "hollow"].contains(where: n.contains) { out.insert(.core) }
        if ["bike", "run", "walk", "jog", "row erg", "elliptical", "stair"].contains(where: n.contains) { out.insert(.cardio) }
        return out
    }

    /// How well a set of logged exercises matches a planned session: an
    /// exact exercise counts 2, a shared focus 1.
    static func match(_ logged: [String], _ session: WorkoutProgram.Session) -> Double {
        let planned = session.exercises.map(\.name)
        let plannedFocus = planned.reduce(into: Set<Focus>()) { $0.formUnion(focus(of: $1)) }
            .union(session.kind == .bike || session.kind == .walk ? [.cardio] : [])
        return logged.reduce(0) { total, name in
            if planned.contains(name) { return total + 2 }
            return total + (focus(of: name).isDisjoint(with: plannedFocus) ? 0 : 1)
        }
    }

    /// The later day this week to swap with today, if what you logged fits
    /// it clearly better than today's plan. Only strength days move.
    static func swapTarget(logged: [String], todayPlan: WorkoutProgram.Session,
                           upcoming: [(date: Date, session: WorkoutProgram.Session)]) -> Date? {
        guard !logged.isEmpty else { return nil }
        let here = match(logged, todayPlan)
        let best = upcoming
            .filter { $0.session.kind == .strength || $0.session.kind == .light }
            .map { (date: $0.date, score: match(logged, $0.session)) }
            .max { $0.score < $1.score }
        guard let best, best.score >= max(2, here + 2) else { return nil }
        return best.date
    }
}
