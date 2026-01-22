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
