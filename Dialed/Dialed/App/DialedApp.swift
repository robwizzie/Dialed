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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    init() {
        // Request notification permissions on app launch
        Task {
            await NotificationManager.shared.checkAuthorizationStatus()
        }
    }

    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(appState)
                .modelContainer(for: [
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
                    TemplateSet.self
                ])
        }
    }
}
