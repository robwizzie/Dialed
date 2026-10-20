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
    case foodLog, workout, weeklyReview, timeline, calendar, devices, strength, progressPhotos, mileHistory, weightTrend, mealPlan, schedule,
         metabolism, wakeUp, calendars, badges, habits, notifications, activity

    var title: String {
        switch self {
        case .workout:  return "Workout plan"
        case .weeklyReview: return "Week in review"
        case .timeline: return "Day timeline"
        case .foodLog:  return "Food log"
        case .calendar: return "Score calendar"
        case .devices:  return "Devices & data check"
        case .strength: return "Strength vs weight"
        case .progressPhotos: return "Progress photos"
        case .mileHistory: return "Mile history"
        case .weightTrend: return "Trend weight"
        case .mealPlan: return "Meal plan"
        case .schedule: return "Schedule"
        case .metabolism: return "Metabolism"
        case .wakeUp: return "Wake-up times & alarm"
        case .calendars: return "Calendars"
        case .badges: return "Badges"
        case .habits: return "Habit heatmap"
        case .notifications: return "Notifications"
        case .activity: return "Suggested activity"
        }
    }

    var icon: String {
        switch self {
        case .workout:  return "dumbbell.fill"
        case .weeklyReview: return "calendar.badge.checkmark"
        case .timeline: return "clock.arrow.circlepath"
        case .foodLog:  return "fork.knife"
        case .calendar: return "calendar"
        case .devices:  return "dot.radiowaves.left.and.right"
        case .strength: return "chart.line.uptrend.xyaxis"
        case .progressPhotos: return "camera.fill"
        case .mileHistory: return "figure.walk"
        case .weightTrend: return "scalemass.fill"
        case .mealPlan: return "calendar.day.timeline.left"
        case .schedule: return "calendar.badge.clock"
        case .metabolism: return "flame.fill"
        case .wakeUp: return "alarm.fill"
        case .calendars: return "calendar"
        case .badges: return "trophy.fill"
        case .habits: return "square.grid.3x3.fill"
        case .notifications: return "bell.fill"
        case .activity: return "figure.mixed.cardio"
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

/// Quick-log sheets available from every tab. `.hub` is the bottom bar's
/// "+" sheet that leads to the rest.
enum QuickLog: String, Identifiable, CaseIterable {
    case hub, meal, snapMeal, scanFood, describeFood, eatingOut, workout, water, weighIn, activity, voice

    var id: String { rawValue }

    /// The ones listed in the tabs' "Log" menus (the hub is the + button).
    static var menuItems: [QuickLog] { allCases.filter { $0 != .hub } }

    var title: String {
        switch self {
        case .hub:     return "Log"
        case .water:   return "Water"
        case .weighIn: return "Weigh-in"
        case .meal:    return "Log food"
        case .snapMeal: return "Snap a meal"
        case .scanFood: return "Scan barcode"
        case .describeFood: return "Describe a meal"
        case .eatingOut: return "Eating out"
        case .workout: return "Log workout"
        case .activity: return "Add an activity"
        case .voice:   return "Voice note"
        }
    }

    var icon: String {
        switch self {
        case .hub:     return "plus"
        case .water:   return "drop.fill"
        case .weighIn: return "scalemass.fill"
        case .meal:    return "fork.knife"
        case .snapMeal: return "camera.fill"
        case .scanFood: return "barcode.viewfinder"
        case .describeFood: return "text.bubble.fill"
        case .eatingOut: return "takeoutbag.and.cup.and.straw.fill"
        case .workout: return "dumbbell.fill"
        case .activity: return "figure.mixed.cardio"
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
    /// "Everything in Dialed", the searchable directory sheet.
    @Published var showDirectory = false

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
