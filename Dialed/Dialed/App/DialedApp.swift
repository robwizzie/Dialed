//
//  DialedApp.swift
//  Dialed
//
//  Created on 2026-01-08
//

import SwiftUI
import SwiftData

@main
struct DialedApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(for: [
                    DayLog.self,
                    FoodEntry.self,
                    WorkoutLog.self,
                    WorkoutExercise.self,
                    ChecklistItem.self
                ])
        }
    }
}
