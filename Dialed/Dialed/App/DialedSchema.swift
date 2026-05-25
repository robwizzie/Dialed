//
//  DialedSchema.swift
//  Dialed
//
//  Single source of truth for the SwiftData schema. Centralizes the model list
//  so we don't have to update every preview-container call site when we add a
//  new @Model class.
//

import Foundation
import SwiftData

enum DialedSchema {
    /// All persistent models registered with SwiftData. Add new models here.
    static let allModels: [any PersistentModel.Type] = [
        // Legacy core
        DayLog.self,
        FoodEntry.self,
        WorkoutLog.self,
        WorkoutExercise.self,
        WorkoutSet.self,
        WorkoutPhoto.self,
        ChecklistItem.self,
        CustomWorkoutType.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateSet.self,

        // Dialed 2.0 — adaptive health OS
        ContextEvent.self,
        BiometricSnapshot.self,
        SleepSession.self,
        PersonalBaseline.self
    ]

    /// Build a ModelContainer with the full schema. Used by previews and the
    /// transient containers some views create before they have a real context.
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(allModels))
    }
}
