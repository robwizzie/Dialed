//
//  AppRouter.swift
//  Dialed
//
//  Shared navigation state for the custom bottom bar. The bar's nested
//  menus can switch tabs, open a quick-log sheet from anywhere, or ask a
//  tab to present one of its own sheets / push one of its screens. Tabs
//  observe their request property and clear it once handled.
//

import SwiftUI

/// Places Home can push to.
enum HomeDestination: String, Hashable, CaseIterable {
    case workout, timeline, tracking, calendar, devices

    var title: String {
        switch self {
        case .workout:  return "Workout plan"
        case .timeline: return "Day timeline"
        case .tracking: return "Detailed tracking"
        case .calendar: return "Score calendar"
        case .devices:  return "Devices & data check"
        }
    }

    var icon: String {
        switch self {
        case .workout:  return "dumbbell.fill"
        case .timeline: return "clock.arrow.circlepath"
        case .tracking: return "checklist"
        case .calendar: return "calendar"
        case .devices:  return "dot.radiowaves.left.and.right"
        }
    }
}

/// Pages of the Health tab.
enum HealthSection: String, CaseIterable, Identifiable {
    case body, sleep, nutrition
    var id: String { rawValue }

    var title: String {
        switch self {
        case .body:      return "Body"
        case .sleep:     return "Sleep"
        case .nutrition: return "Nutrition"
        }
    }

    var icon: String {
        switch self {
        case .body:      return "figure.stand"
        case .sleep:     return "moon.fill"
        case .nutrition: return "fork.knife"
        }
    }
}

/// Quick-log sheets available from every tab.
enum QuickLog: String, Identifiable, CaseIterable {
    case water, weighIn, meal, voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water:   return "Water"
        case .weighIn: return "Weigh in"
        case .meal:    return "Meal"
        case .voice:   return "Voice note"
        }
    }

    var icon: String {
        switch self {
        case .water:   return "drop.fill"
        case .weighIn: return "scalemass.fill"
        case .meal:    return "fork.knife"
        case .voice:   return "mic.fill"
        }
    }
}

extension Notification.Name {
    /// Posted after a quick-log sheet closes so visible tabs re-read data.
    static let dialedDataDidChange = Notification.Name("dialedDataDidChange")
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var quickLog: QuickLog?

    /// One-shot requests; the owning tab handles then clears them.
    @Published var homeSheet: HomeView.HomeSheet?
    @Published var homePush: HomeDestination?
    @Published var challengeSheet: ChallengeView.Sheet?
    /// Page the Health tab shows (Body / Sleep / Nutrition).
    @Published var healthSection: HealthSection = .body

    func select(_ tab: AppTab) {
        guard tab != self.tab else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            self.tab = tab
        }
    }

    func openHome(_ sheet: HomeView.HomeSheet) {
        select(.home)
        homeSheet = sheet
    }

    func openHome(_ destination: HomeDestination) {
        select(.home)
        homePush = destination
    }

    func openHealth(_ section: HealthSection) {
        healthSection = section
        select(.trends)
    }

    func openChallenge(_ sheet: ChallengeView.Sheet) {
        select(.challenge)
        challengeSheet = sheet
    }
}
