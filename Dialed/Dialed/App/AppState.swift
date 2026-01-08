//
//  AppState.swift
//  Dialed
//
//  Global app state management
//

import Foundation
import SwiftUI

class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    @Published var currentDate: Date = Date()

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func checkForNewDay() {
        let calendar = Calendar.current
        let now = Date()

        // Use 4 AM cutoff for day changes
        let cutoffHour = 4
        let currentHour = calendar.component(.hour, from: now)

        // Determine the "app day" (if before 4 AM, still counts as previous day)
        var appDay = now
        if currentHour < cutoffHour {
            appDay = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        }

        if !calendar.isDate(currentDate, inSameDayAs: appDay) {
            currentDate = appDay
            // Trigger day finalization logic here
            NotificationCenter.default.post(name: .dayDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let dayDidChange = Notification.Name("dayDidChange")
}
