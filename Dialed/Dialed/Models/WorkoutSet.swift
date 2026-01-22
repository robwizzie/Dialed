//
//  WorkoutSet.swift
//  Dialed
//
//  Individual set within an exercise - tracks weight, reps, rest
//

import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var id: UUID
    var setNumber: Int              // 1, 2, 3, etc.
    var reps: Int                   // Repetitions completed
    var weightLbs: Double           // Weight used
    var restSeconds: Int?           // Rest time after this set
    var notes: String?              // Optional notes (e.g., "felt easy", "struggled on last rep")
    var completedAt: Date           // When this set was completed
    var isWarmup: Bool              // Mark as warmup set
    var rpe: Int?                   // Rate of Perceived Exertion (1-10 scale)

    // Relationship
    var exercise: WorkoutExercise?

    init(setNumber: Int, reps: Int, weightLbs: Double, restSeconds: Int? = nil, notes: String? = nil, isWarmup: Bool = false, rpe: Int? = nil) {
        self.id = UUID()
        self.setNumber = setNumber
        self.reps = reps
        self.weightLbs = weightLbs
        self.restSeconds = restSeconds
        self.notes = notes
        self.completedAt = Date()
        self.isWarmup = isWarmup
        self.rpe = rpe
    }

    // MARK: - Computed Properties

    /// Calculate volume for this set (weight × reps)
    var volume: Double {
        return weightLbs * Double(reps)
    }

    /// Formatted weight display
    var weightDisplay: String {
        if weightLbs.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weightLbs)) lbs"
        } else {
            return String(format: "%.1f lbs", weightLbs)
        }
    }

    /// Formatted rest time
    var restDisplay: String? {
        guard let rest = restSeconds else { return nil }
        if rest < 60 {
            return "\(rest)s"
        } else {
            let minutes = rest / 60
            let seconds = rest % 60
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
    }

    /// Compare to another set to see if there's improvement
    func isImprovementOver(_ previousSet: WorkoutSet) -> Bool {
        // Better if more weight at same or more reps
        if weightLbs > previousSet.weightLbs {
            return reps >= previousSet.reps
        }
        // Or same weight with more reps
        if weightLbs == previousSet.weightLbs {
            return reps > previousSet.reps
        }
        return false
    }
}
