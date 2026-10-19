//
//  WorkoutProgram.swift
//  Dialed
//
//  The basement + Peaches plan for the run-up to the goal day: three
//  strength days (barbell, bench, cable, dumbbells), two bike-interval
//  days, daily walks with Peaches and a long walk/run on Thursdays.
//  Phases (base → build → peak → event week) are counted back from the
//  goal day, so moving the date moves the plan. Pure Foundation, tested.
//

import Foundation

enum WorkoutProgram {

    struct Exercise: Hashable {
        let name: String
        let prescription: String
    }

    struct Session: Equatable {
        enum Kind: String { case strength, bike, walk, light, rest, event }
        let kind: Kind
        let title: String
        let minutes: Int
        let exercises: [Exercise]
        /// The walk with Peaches that goes with it, if any.
        let walk: String?
        let notes: [String]

        var symbol: String {
            switch kind {
            case .strength: return "dumbbell.fill"
            case .bike:     return "bicycle"
            case .walk:     return "figure.walk"
            case .light:    return "figure.cooldown"
            case .rest:     return "bed.double.fill"
            case .event:    return "sparkles"
            }
        }
    }

    enum Phase: String {
        case base, build, peak, eventWeek, after

        var title: String {
            switch self {
            case .base:      return "Base"
            case .build:     return "Build"
            case .peak:      return "Peak"
            case .eventWeek: return "Event week"
            case .after:     return "Done"
            }
        }

        var focus: String {
            switch self {
            case .base:      return "Learn the movements, moderate weights. Just hit every session."
            case .build:     return "Add weight or reps every week. Circuit C gets a 4th round."
            case .peak:      return "Hardest week. Add 15 min of bike after Strength A and B."
            case .eventWeek: return "Taper. Walks and one light session. No crash dieting, no cutting water."
            case .after:     return "You made it. Pick a new goal day to start the next block."
            }
        }
    }

    // MARK: - Sessions

    static let strengthA = Session(
        kind: .strength, title: "Strength A · Push + legs", minutes: 45,
        exercises: [
            Exercise(name: "Barbell back squat", prescription: "4 × 8"),
            Exercise(name: "Bench press", prescription: "4 × 8"),
            Exercise(name: "Dumbbell walking lunge", prescription: "3 × 10 / leg"),
            Exercise(name: "Cable fly", prescription: "3 × 12"),
            Exercise(name: "Dumbbell shoulder press", prescription: "3 × 10"),
            Exercise(name: "Cable woodchop + 1-min plank", prescription: "3 × 12 / side")
        ],
        walk: "30-min walk with Peaches",
        notes: ["Rest 60–90 s. Last 2 reps hard but clean."]
    )

    static let strengthB = Session(
        kind: .strength, title: "Strength B · Pull + hinge", minutes: 45,
        exercises: [
            Exercise(name: "Barbell Romanian deadlift", prescription: "4 × 8"),
            Exercise(name: "Cable lat pulldown", prescription: "4 × 10"),
            Exercise(name: "One-arm dumbbell row (bench)", prescription: "3 × 10 / arm"),
            Exercise(name: "Cable face pull", prescription: "3 × 15"),
            Exercise(name: "Dumbbell goblet squat", prescription: "3 × 12"),
            Exercise(name: "Cable curl + rope pushdown superset", prescription: "3 × 12 each")
        ],
        walk: "30-min walk with Peaches",
        notes: ["Rest 60–90 s. Last 2 reps hard but clean."]
    )

    static func strengthC(rounds: Int) -> Session {
        Session(
            kind: .strength, title: "Strength C · Full-body circuit", minutes: 40,
            exercises: [
                Exercise(name: "Dumbbell thruster", prescription: "45 s"),
                Exercise(name: "Push-up (feet on bench when easy)", prescription: "45 s"),
                Exercise(name: "Cable row", prescription: "45 s"),
                Exercise(name: "Dumbbell reverse lunge", prescription: "45 s"),
                Exercise(name: "Kettlebell / dumbbell swing", prescription: "45 s"),
                Exercise(name: "Mountain climbers", prescription: "45 s")
            ],
            walk: "30-min walk with Peaches",
            notes: ["\(rounds) rounds · 45 s on, 15 s off · 90 s between rounds."]
        )
    }

    static func bike(week: Int, withLongWalk: Bool) -> Session {
        let intervals = week <= 2
            ? "8 rounds · 30 s hard / 90 s easy"
            : "10 rounds · 40 s hard / 80 s easy"
        return Session(
            kind: .bike, title: "Bike intervals", minutes: 25,
            exercises: [
                Exercise(name: "Easy warm-up", prescription: "5 min"),
                Exercise(name: "Intervals", prescription: intervals),
                Exercise(name: "Cool-down", prescription: "5 min")
            ],
            walk: withLongWalk ? "45-min long walk with Peaches" : "30-min walk with Peaches",
            notes: ["Hard = you can't talk. Easy = full recovery."]
        )
    }

    static func longWalk(week: Int) -> Session {
        Session(
            kind: .walk, title: week <= 1 ? "Long walk with Peaches" : "Walk / run with Peaches",
            minutes: 50,
            exercises: week <= 1
                ? [Exercise(name: "Brisk walk (can talk, can't sing)", prescription: "45–60 min")]
                : [Exercise(name: "Jog 2 min / walk 3 min", prescription: "× 6–8"),
                   Exercise(name: "Easy walk home", prescription: "10 min")],
            walk: nil,
            notes: ["Build Peaches up gradually too: skip hot pavement, no running right after she eats."]
        )
    }

    static let rest = Session(
        kind: .rest, title: "Rest day", minutes: 0, exercises: [],
        walk: "Easy walk with Peaches (optional)",
        notes: ["Recovery is where the work turns into results. Sleep 7.5+ hours."]
    )

    static let light = Session(
        kind: .light, title: "Light full-body · ~60%", minutes: 30,
        exercises: [
            Exercise(name: "Goblet squat", prescription: "2 × 10"),
            Exercise(name: "Push-up", prescription: "2 × 10"),
            Exercise(name: "Cable row", prescription: "2 × 12"),
            Exercise(name: "Dumbbell RDL", prescription: "2 × 10")
        ],
        walk: "30-min walk with Peaches",
        notes: ["Keep it easy — you want to feel fresh, not sore. No new foods this week."]
    )

    static let eventDay = Session(
        kind: .event, title: "The big day", minutes: 0, exercises: [],
        walk: "Morning walk with Peaches",
        notes: ["Normal breakfast, normal water. Go enjoy it."]
    )

    // MARK: - Calendar

    /// 1-based week of the program for `date`.
    static func week(of date: Date, start: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        return max(1, days / 7 + 1)
    }

    static func daysToGoal(from date: Date, goal: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: goal)).day ?? 0
    }

    static func phase(on date: Date, start: Date, goal: Date, calendar: Calendar = .current) -> Phase {
        let left = daysToGoal(from: date, goal: goal, calendar: calendar)
        if left < 0 { return .after }
        if left <= 3 { return .eventWeek }
        if left <= 10 { return .peak }
        return week(of: date, start: start, calendar: calendar) <= 1 ? .base : .build
    }

    static func session(on date: Date, start: Date, goal: Date, calendar: Calendar = .current) -> Session {
        let left = daysToGoal(from: date, goal: goal, calendar: calendar)
        let wk = week(of: date, start: start, calendar: calendar)
        let ph = phase(on: date, start: start, goal: goal, calendar: calendar)

        switch left {
        case 0:      return eventDay
        case 1, 2:   return light
        case 3:      return strengthC(rounds: 4)   // last hard session
        case ..<0:   return rest
        default:     break
        }

        var s: Session
        switch calendar.component(.weekday, from: date) {   // 1 = Sunday
        case 2:  s = strengthA
        case 3:  s = bike(week: wk, withLongWalk: false)
        case 4:  s = strengthB
        case 5:  s = longWalk(week: wk)
        case 6:  s = strengthC(rounds: ph == .base ? 3 : 4)
        case 7:  s = bike(week: wk, withLongWalk: true)
        default: s = rest
        }
        if ph == .peak, s == strengthA || s == strengthB {
            s = Session(kind: s.kind, title: s.title, minutes: s.minutes + 15,
                        exercises: s.exercises + [Exercise(name: "Bike, steady", prescription: "15 min")],
                        walk: s.walk, notes: s.notes)
        }
        return s
    }
}
