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

    /// Last major version the user has seen the What's New sheet for.
    /// Bump WhatsNew.currentVersion when there's a new sheet to show; the
    /// sheet auto-presents when this trails the current version.
    @Published var lastSeenWhatsNewVersion: Int {
        didSet {
            UserDefaults.standard.set(lastSeenWhatsNewVersion, forKey: "lastSeenWhatsNewVersion")
        }
    }

    @Published var currentDate: Date = Date()

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.lastSeenWhatsNewVersion = UserDefaults.standard.integer(forKey: "lastSeenWhatsNewVersion")
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    /// True when the current build has a What's New page the user hasn't
    /// seen. Suppressed during onboarding — first-run users get the
    /// onboarding flow instead, not a "what's new" pitch.
    var shouldShowWhatsNew: Bool {
        hasCompletedOnboarding && lastSeenWhatsNewVersion < WhatsNew.currentVersion
    }

    func markWhatsNewSeen() {
        lastSeenWhatsNewVersion = WhatsNew.currentVersion
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
