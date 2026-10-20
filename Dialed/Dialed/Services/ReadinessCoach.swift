//
//  ReadinessCoach.swift
//  Dialed
//
//  Trains to how you showed up today. Readiness under 45 (or an illness
//  watch) turns a hard day into an easy walk and mobility; a "Steady"
//  45–69 swaps heavy lifting for intervals (or the same lifts lighter);
//  70–79 is the plan as written; 80+ picks one or two lifts closest to a
//  milestone and suggests the PR attempt, with a warm-up. Pure
//  Foundation, tested.
//

import Foundation

enum ReadinessCoach {

    enum Mode: String, Codable { case recovery, lighter, asPlanned, prAttempt }

    struct Inputs {
        var readiness: Int?
        /// Illness watch at "watch" or worse.
        var illnessWatch = false
        var sleepScore: Int?
        var session: WorkoutProgram.Session
        /// Strength or bike sessions logged in the last three days.
        var recentHardDays = 0
        /// Your best sets per exercise, for PR picks.
        var bests: [String: StrengthMilestones.Best] = [:]
    }

    struct Attempt: Equatable, Codable {
        var exercise: String
        var weight: Double
        var reps: Int
        /// Heaviest you've done, and your estimated max.
        var lastWeight: Double
        var estimatedMax: Double

        /// "Bench press: try 160 × 6 · 5 lb over your best · est. max 195"
        var text: String {
            let over = weight - lastWeight
            return "\(exercise): try \(lbs(weight)) × \(reps) · \(lbs(over)) lb over your best · est. max \(lbs(estimatedMax))"
        }

        /// Ramp-up sets before the attempt.
        var warmUp: String {
            let ramp = [0.5, 0.7, 0.85].map { lbs(((weight * $0) / 5).rounded() * 5) }
            return "Warm up: \(ramp[0]) × 8, \(ramp[1]) × 4, \(ramp[2]) × 2, rest 2–3 min, then go."
        }
    }

    struct Recommendation: Equatable {
        var mode: Mode
        var label: String
        var title: String
        var detail: String
        var reasons: [String]
        /// Today's session if you take the advice (nil = keep the plan).
        var swap: WorkoutProgram.Session?
        var attempts: [Attempt] = []

        /// Something to act on (a swap or a PR attempt), not just a nod.
        var isActionable: Bool { swap != nil || !attempts.isEmpty }
    }

    // MARK: - Labels

    /// "Go easy" / "Steady" / "Ready" / "Primed"
    static func label(_ readiness: Int) -> String {
        switch readiness {
        case ..<45: return "Go easy"
        case ..<70: return "Steady"
        case ..<80: return "Ready"
        default:    return "Primed"
        }
    }

    // MARK: - Recommend

    static func recommend(_ i: Inputs) -> Recommendation? {
        guard let r = i.readiness else { return nil }
        let s = i.session
        let hard = s.kind == .strength || s.kind == .bike
        var reasons = ["Readiness \(r) · \(label(r))"]
        if let sleep = i.sleepScore { reasons.append("Sleep score \(sleep)") }
        if i.recentHardDays >= 2 { reasons.append("\(i.recentHardDays) hard sessions in the last 3 days") }

        // Recovery: low readiness or the body fighting something.
        if r < 45 || i.illnessWatch {
            if i.illnessWatch { reasons.insert("Illness watch is on", at: 0) }
            return Recommendation(
                mode: .recovery, label: label(r),
                title: hard ? "Make it a recovery day" : "Keep today easy",
                detail: hard
                    ? "Swap \(s.title) for an easy walk and 15 minutes of mobility. Your streak stays alive and the hard work moves to a better day."
                    : "Today's plan is already easy. Stay there, sleep early, drink plenty.",
                reasons: reasons, swap: hard ? recoverySession : nil)
        }

        // Steady: lighter version of a heavy day.
        if r < 70 || (r < 80 && i.recentHardDays >= 3) {
            guard s.kind == .strength else {
                return Recommendation(mode: .asPlanned, label: label(r), title: "Plan holds",
                                      detail: s.kind == .bike ? "Ride the intervals at about 90% effort." : "Go as planned.",
                                      reasons: reasons, swap: nil)
            }
            return Recommendation(
                mode: .lighter, label: label(r), title: "Intervals instead of heavy lifting",
                detail: "Your body's at \(r). Ride 25 min of intervals today, or keep the lifts at about 85% with one fewer set. The heavy session waits for a better day.",
                reasons: reasons, swap: intervalSession)
        }

        // Ready: as written.
        if r < 80 || s.kind != .strength {
            return Recommendation(mode: .asPlanned, label: label(r), title: "Train as planned",
                                  detail: s.kind == .strength ? "Good day to add 5 lb where the last set felt easy." : "Go as planned.",
                                  reasons: reasons, swap: nil)
        }

        // Primed: go for a PR on the lifts closest to a milestone.
        let picks = prAttempts(session: s, bests: i.bests)
        guard !picks.isEmpty else {
            return Recommendation(mode: .asPlanned, label: label(r), title: "You're primed",
                                  detail: "Push the top sets today: add 5 lb wherever the last set moved fast.",
                                  reasons: reasons, swap: nil)
        }
        return Recommendation(
            mode: .prAttempt, label: label(r), title: "Go for a PR",
            detail: "Readiness \(r) is a green light. One top set on " + picks.map(\.exercise).joined(separator: " and ") + ", then the rest as planned.",
            reasons: reasons, swap: nil, attempts: picks)
    }

    /// Up to two lifts from today's session, closest to their next
    /// milestone (by share of the weight still to go).
    static func prAttempts(session: WorkoutProgram.Session, bests: [String: StrengthMilestones.Best]) -> [Attempt] {
        let candidates = session.exercises.compactMap { e -> (Attempt, Double)? in
            // Timed work ("45 s") isn't a PR lift.
            guard StrengthProgression.parse(e.prescription)?.reps != nil,
                  let best = bests[e.name], best.heaviest.weight > 0,
                  let next = StrengthMilestones.nextMilestone(for: best) else { return nil }
            let heaviest = best.heaviest.weight
            let step: Double = 5
            // +5 lb at the same reps; a single when the milestone is a bigger
            // jump your estimated max already covers.
            let attempt = next.withinReach && next.target > heaviest + step
                ? Attempt(exercise: e.name, weight: next.target, reps: 1, lastWeight: heaviest, estimatedMax: best.e1RM.rounded())
                : Attempt(exercise: e.name, weight: min(next.target, heaviest + step), reps: max(1, best.heaviest.reps),
                          lastWeight: heaviest, estimatedMax: best.e1RM.rounded())
            return (attempt, next.remaining / heaviest)
        }
        return candidates.sorted { $0.1 < $1.1 }.prefix(2).map(\.0)
    }

    // MARK: - Swap sessions

    static let recoverySession = WorkoutProgram.Session(
        kind: .light, title: "Recovery · walk + mobility", minutes: 30,
        exercises: [
            WorkoutProgram.Exercise(name: "Easy walk", prescription: "15 min"),
            WorkoutProgram.Exercise(name: "Hip & hamstring mobility", prescription: "5 min"),
            WorkoutProgram.Exercise(name: "Thoracic & shoulder mobility", prescription: "5 min"),
            WorkoutProgram.Exercise(name: "Box breathing", prescription: "3 min")
        ],
        walk: "Daily mile · easy walk",
        notes: ["Readiness swap: easy all the way. You should finish fresher than you started."])

    static let intervalSession = WorkoutProgram.Session(
        kind: .bike, title: "Intervals · 25 min", minutes: 25,
        exercises: [
            WorkoutProgram.Exercise(name: "Easy warm-up", prescription: "5 min"),
            WorkoutProgram.Exercise(name: "Intervals", prescription: "8 rounds · 30 s hard / 90 s easy"),
            WorkoutProgram.Exercise(name: "Cool-down", prescription: "5 min")
        ],
        walk: "Daily mile · walk or run",
        notes: ["Readiness swap: hard = you can't talk, easy = full recovery."])

    static func session(for mode: Mode) -> WorkoutProgram.Session? {
        switch mode {
        case .recovery: return recoverySession
        case .lighter:  return intervalSession
        default:        return nil
        }
    }

    private static func lbs(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Today's choice

/// What you did with today's advice: took the swap, set PR attempts, or
/// kept the plan. One day at a time.
enum ReadinessChoiceStore {
    private static let key = "readiness.choice"
    private static let readinessKey = "readiness.today"

    struct Choice: Codable, Equatable {
        var day: String
        var mode: ReadinessCoach.Mode
        /// false = "Keep plan"
        var applied: Bool
        var attempts: [ReadinessCoach.Attempt] = []
    }

    static func choice(for day: Date) -> Choice? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let c = try? JSONDecoder().decode(Choice.self, from: data),
              c.day == WorkoutPlanStore.key(day) else { return nil }
        return c
    }

    static func set(_ choice: Choice) {
        if let data = try? JSONEncoder().encode(choice) { UserDefaults.standard.set(data, forKey: key) }
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    static func clear(day: Date) {
        guard choice(for: day) != nil else { return }
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    /// The swapped-in session for `day`, if you took one.
    static func overrideSession(for day: Date) -> WorkoutProgram.Session? {
        guard let c = choice(for: day), c.applied else { return nil }
        return ReadinessCoach.session(for: c.mode)
    }

    /// PR attempt for an exercise today, if you said yes.
    static func attempt(_ exercise: String, on day: Date) -> ReadinessCoach.Attempt? {
        guard let c = choice(for: day), c.applied else { return nil }
        return c.attempts.first { $0.exercise == exercise }
    }

    // Today's readiness, cached by Home so the logger can show the same advice.

    static func cacheReadiness(_ score: Int?, illness: Bool, sleep: Int?, day: Date = Date()) {
        UserDefaults.standard.set(["day": WorkoutPlanStore.key(day), "score": score ?? -1,
                                   "illness": illness, "sleep": sleep ?? -1] as [String: Any], forKey: readinessKey)
    }

    static func cachedReadiness(day: Date = Date()) -> (score: Int, illness: Bool, sleep: Int?)? {
        guard let d = UserDefaults.standard.dictionary(forKey: readinessKey),
              d["day"] as? String == WorkoutPlanStore.key(day),
              let score = d["score"] as? Int, score >= 0 else { return nil }
        let sleep = d["sleep"] as? Int
        return (score, d["illness"] as? Bool ?? false, sleep.flatMap { $0 >= 0 ? $0 : nil })
    }
}
