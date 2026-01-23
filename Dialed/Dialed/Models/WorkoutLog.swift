//
//  WorkoutLog.swift
//  Dialed
//
//  Workout details (simplified - no exercise tracking in MVP)
//

import Foundation
import SwiftData

@Model
final class WorkoutLog {
    var id: UUID
    var dayDate: Date
    var tag: String  // WorkoutTag rawValue
    var workoutScore: Int  // 0-5 quality rating
    var notes: String?

    // Auto-detected data from HealthKit
    var detectedFromHealth: Bool
    var healthKitWorkoutType: String?
    var healthKitWorkoutID: String?  // UUID string for linking to Apple Health workout
    var durationMinutes: Int?
    var caloriesBurned: Int?
    var averageHeartRate: Double?
    var maxHeartRate: Double?

    // Timestamps
    var startTime: Date?
    var endTime: Date?
    var loggedAt: Date

    // Relationships
    @Relationship(deleteRule: .cascade) var exercises: [WorkoutExercise]?
    @Relationship(deleteRule: .cascade) var photos: [WorkoutPhoto]?

    init(
        dayDate: Date,
        tag: String,
        workoutScore: Int,
        notes: String? = nil,
        detectedFromHealth: Bool = false,
        healthKitWorkoutID: String? = nil
    ) {
        self.id = UUID()
        self.dayDate = dayDate
        self.tag = tag
        self.workoutScore = workoutScore
        self.notes = notes
        self.detectedFromHealth = detectedFromHealth
        self.healthKitWorkoutID = healthKitWorkoutID
        self.loggedAt = Date()
    }

    // Convenience initializer for built-in tags
    convenience init(
        dayDate: Date,
        tag: Constants.WorkoutTag,
        workoutScore: Int,
        notes: String? = nil,
        detectedFromHealth: Bool = false,
        healthKitWorkoutID: String? = nil
    ) {
        self.init(
            dayDate: dayDate,
            tag: tag.rawValue,
            workoutScore: workoutScore,
            notes: notes,
            detectedFromHealth: detectedFromHealth,
            healthKitWorkoutID: healthKitWorkoutID
        )
    }

    var workoutTag: Constants.WorkoutTag? {
        Constants.WorkoutTag(rawValue: tag)
    }
    
    /// Whether this workout is linked to an Apple Health workout
    var isLinkedToHealth: Bool {
        healthKitWorkoutID != nil
    }
}
