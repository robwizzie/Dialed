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
    var notes: String?
    var createdAt: Date

    // Relationships
    var workoutLog: WorkoutLog?
    @Relationship(deleteRule: .cascade) var workoutSets: [WorkoutSet]?

    init(exerciseName: String, notes: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.exerciseName = exerciseName
        self.notes = notes
        self.createdAt = Date()
        self.workoutSets = []
    }

    // MARK: - Computed Properties

    /// Total number of sets (including warmups)
    var totalSets: Int {
        return workoutSets?.count ?? 0
    }

    /// Total number of working sets (excluding warmups)
    var workingSets: Int {
        return workoutSets?.filter { !$0.isWarmup }.count ?? 0
    }

    /// Total volume for this exercise (sum of all set volumes)
    var totalVolume: Double {
        return workoutSets?.reduce(0) { $0 + $1.volume } ?? 0
    }

    /// Average weight across all working sets
    var averageWeight: Double {
        let working = workoutSets?.filter { !$0.isWarmup } ?? []
        guard !working.isEmpty else { return 0 }
        let total = working.reduce(0.0) { $0 + $1.weightLbs }
        return total / Double(working.count)
    }

    /// Average reps across all working sets
    var averageReps: Double {
        let working = workoutSets?.filter { !$0.isWarmup } ?? []
        guard !working.isEmpty else { return 0 }
        let total = working.reduce(0) { $0 + $1.reps }
        return Double(total) / Double(working.count)
    }

    /// Top set (highest weight × reps)
    var topSet: WorkoutSet? {
        return workoutSets?.filter { !$0.isWarmup }.max { $0.volume < $1.volume }
    }

    /// Display string for sets (e.g., "3 sets")
    var setsDisplay: String {
        let working = workingSets
        let warmup = totalSets - working
        if warmup > 0 {
            return "\(working) sets + \(warmup) warmup"
        }
        return "\(working) \(working == 1 ? "set" : "sets")"
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
