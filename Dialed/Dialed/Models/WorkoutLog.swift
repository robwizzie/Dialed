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
    var durationMinutes: Int?
    var caloriesBurned: Int?
    var averageHeartRate: Double?
    var maxHeartRate: Double?

    // Timestamps
    var startTime: Date?
    var endTime: Date?
    var loggedAt: Date

    // Relationship to exercises
    @Relationship(deleteRule: .cascade) var exercises: [WorkoutExercise]?

    init(
        dayDate: Date,
        tag: Constants.WorkoutTag,
        workoutScore: Int,
        notes: String? = nil,
        detectedFromHealth: Bool = false
    ) {
        self.id = UUID()
        self.dayDate = dayDate
        self.tag = tag.rawValue
        self.workoutScore = workoutScore
        self.notes = notes
        self.detectedFromHealth = detectedFromHealth
        self.loggedAt = Date()
    }

    var workoutTag: Constants.WorkoutTag? {
        Constants.WorkoutTag(rawValue: tag)
    }
}
