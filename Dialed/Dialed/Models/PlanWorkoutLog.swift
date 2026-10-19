//
//  PlanWorkoutLog.swift
//  Dialed
//
//  What you actually did on a workout-plan day. One PlanWorkoutLog per
//  logged session (keyed by the plan's "yyyy-MM-dd" day key) and one
//  flat PlanSetLog per set, linked by `workoutID` (no relationship, so
//  queries for "last time I benched" stay simple predicates).
//

import Foundation
import SwiftData

@Model
final class PlanWorkoutLog {
    var id: UUID = UUID()
    /// WorkoutPlanStore.key(day) — "2026-10-19".
    var dayKey: String = ""
    var date: Date = Date()
    var title: String = ""
    /// WorkoutProgram.Session.Kind rawValue.
    var kindRaw: String = ""
    var notes: String = ""
    /// Bike / walk sessions.
    var durationMinutes: Double?
    var distanceMiles: Double?
    var savedAt: Date = Date()

    init(dayKey: String, date: Date, title: String, kindRaw: String) {
        self.id = UUID()
        self.dayKey = dayKey
        self.date = date
        self.title = title
        self.kindRaw = kindRaw
        self.savedAt = Date()
    }
}

@Model
final class PlanSetLog {
    var id: UUID = UUID()
    var workoutID: UUID = UUID()
    /// Day of the session (start of day), copied for date-ordered queries.
    var date: Date = Date()
    var exerciseName: String = ""
    var exerciseOrder: Int = 0
    var setIndex: Int = 0
    var weightLbs: Double = 0
    var reps: Int = 0
    var targetReps: Int?
    var completed: Bool = false

    init(workoutID: UUID, date: Date, exerciseName: String, exerciseOrder: Int,
         setIndex: Int, weightLbs: Double, reps: Int, targetReps: Int?, completed: Bool) {
        self.id = UUID()
        self.workoutID = workoutID
        self.date = date
        self.exerciseName = exerciseName
        self.exerciseOrder = exerciseOrder
        self.setIndex = setIndex
        self.weightLbs = weightLbs
        self.reps = reps
        self.targetReps = targetReps
        self.completed = completed
    }

    var asLoggedSet: StrengthProgression.LoggedSet {
        StrengthProgression.LoggedSet(weight: weightLbs, reps: reps, completed: completed)
    }
}
