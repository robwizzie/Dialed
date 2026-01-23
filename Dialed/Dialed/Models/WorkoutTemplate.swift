//
//  WorkoutTemplate.swift
//  Dialed
//
//  Workout templates for saving and reusing workouts
//

import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID
    var name: String
    var workoutTag: String?  // Optional tag for this template
    var notes: String?
    var createdAt: Date
    var lastUsedAt: Date?

    @Relationship(deleteRule: .cascade) var templateExercises: [TemplateExercise]?

    init(
        name: String,
        workoutTag: String? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.workoutTag = workoutTag
        self.notes = notes
        self.createdAt = Date()
    }
}

@Model
final class TemplateExercise {
    var id: UUID
    var exerciseName: String
    var notes: String?
    var orderIndex: Int

    var template: WorkoutTemplate?
    @Relationship(deleteRule: .cascade) var templateSets: [TemplateSet]?

    init(
        exerciseName: String,
        notes: String? = nil,
        orderIndex: Int = 0
    ) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.notes = notes
        self.orderIndex = orderIndex
    }
}

@Model
final class TemplateSet {
    var id: UUID
    var setNumber: Int
    var reps: Int
    var weightLbs: Double
    var restSeconds: Int?
    var notes: String?
    var isWarmup: Bool

    var exercise: TemplateExercise?

    init(
        setNumber: Int,
        reps: Int,
        weightLbs: Double,
        restSeconds: Int? = nil,
        notes: String? = nil,
        isWarmup: Bool = false
    ) {
        self.id = UUID()
        self.setNumber = setNumber
        self.reps = reps
        self.weightLbs = weightLbs
        self.restSeconds = restSeconds
        self.notes = notes
        self.isWarmup = isWarmup
    }
}
