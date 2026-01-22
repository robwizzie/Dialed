//
//  WorkoutPhoto.swift
//  Dialed
//
//  Progress photo attached to a workout
//

import Foundation
import SwiftData

@Model
final class WorkoutPhoto {
    var id: UUID
    var filename: String        // Stored in Documents directory
    var capturedAt: Date
    var notes: String?

    // Relationship
    var workoutLog: WorkoutLog?

    init(filename: String, notes: String? = nil) {
        self.id = UUID()
        self.filename = filename
        self.capturedAt = Date()
        self.notes = notes
    }

    // Full file path
    var fileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(filename)
    }
}
