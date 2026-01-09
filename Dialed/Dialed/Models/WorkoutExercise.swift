//
//  WorkoutExercise.swift
//  Dialed
//
//  Model for individual exercises within a workout
//

import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    var id: UUID
    var date: Date
    var exerciseName: String
    var sets: Int
    var reps: Int
    var weightLbs: Double
    var notes: String?
    var createdAt: Date

    // Relationship to workout log
    var workoutLog: WorkoutLog?

    init(exerciseName: String, sets: Int, reps: Int, weightLbs: Double, notes: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.weightLbs = weightLbs
        self.notes = notes
        self.createdAt = Date()
    }

    // Get previous session for this exercise to track progress
    static func getPreviousSession(
        for exerciseName: String,
        before date: Date,
        context: ModelContext
    ) -> WorkoutExercise? {
        let fetchDescriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { exercise in
                exercise.exerciseName == exerciseName && exercise.date < date
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        return try? context.fetch(fetchDescriptor).first
    }
}

// Common exercise names for quick selection
extension WorkoutExercise {
    enum CommonExercise: String, CaseIterable {
        case benchPress = "Bench Press"
        case squat = "Squat"
        case deadlift = "Deadlift"
        case overheadPress = "Overhead Press"
        case barbellRow = "Barbell Row"
        case pullUp = "Pull-Up"
        case dip = "Dip"
        case legPress = "Leg Press"
        case legCurl = "Leg Curl"
        case legExtension = "Leg Extension"
        case bicepCurl = "Bicep Curl"
        case tricepExtension = "Tricep Extension"
        case lateralRaise = "Lateral Raise"
        case cableFly = "Cable Fly"
        case latPulldown = "Lat Pulldown"
        case seatedRow = "Seated Row"
        case shoulderPress = "Shoulder Press"
        case inclineBench = "Incline Bench Press"
        case declineBench = "Decline Bench Press"
        case frontSquat = "Front Squat"
        case romanianDeadlift = "Romanian Deadlift"
        case lunges = "Lunges"
        case calfRaise = "Calf Raise"
        case facePull = "Face Pull"
        case shrug = "Shrug"

        static var grouped: [String: [CommonExercise]] {
            [
                "Chest": [.benchPress, .inclineBench, .declineBench, .cableFly, .dip],
                "Back": [.deadlift, .barbellRow, .pullUp, .latPulldown, .seatedRow, .facePull],
                "Legs": [.squat, .frontSquat, .legPress, .legCurl, .legExtension, .lunges, .calfRaise],
                "Shoulders": [.overheadPress, .shoulderPress, .lateralRaise, .shrug],
                "Arms": [.bicepCurl, .tricepExtension]
            ]
        }
    }
}
