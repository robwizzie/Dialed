//
//  AppDirectory.swift
//  Dialed
//
//  Everything in Dialed, in one searchable list: grouped by what it's for
//  (Food, Body, Move, Plan, Compete, Progress, Setup), with an icon and a
//  one-line description. The screen that shows it maps each entry's
//  `target` to a tab, a Home page or a sheet. Pure Foundation, tested.
//

import Foundation

enum AppDirectory {

    enum Group: String, CaseIterable, Identifiable {
        case food, body, move, plan, compete, progress, setup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .food:     return "Food"
            case .body:     return "Body"
            case .move:     return "Move"
            case .plan:     return "Plan"
            case .compete:  return "Compete"
            case .progress: return "Progress"
            case .setup:    return "Setup"
            }
        }
    }

    /// Where an entry goes. Kept as plain cases so this file stays free of
    /// the app's view and router types.
    enum Target: String, Equatable {
        case foodLog, mealPlan, eatingOut, scanBarcode
        case trendWeight, metabolism, progressPhotos, strength, sleep, body
        case workoutPlan, mileHistory, suggestedActivity
        case schedule, wakeUp, calendars
        case challenge, weeklyReport, sideBets, wrapped
        case badges, habitHeatmap, weekInReview, scoreCalendar, timeline
        case devices, customizeHome, notifications
    }

    struct Entry: Identifiable, Equatable {
        var target: Target
        var group: Group
        var title: String
        var subtitle: String
        var icon: String
        /// Other words people search with ("weight", "bmr", "alarm"…).
        var keywords: [String] = []

        var id: String { target.rawValue }
    }

    struct Section: Identifiable, Equatable {
        var group: Group
        var entries: [Entry]
        var id: String { group.rawValue }
    }

    static let all: [Entry] = [
        // Food
        Entry(target: .foodLog, group: .food, title: "Food log", subtitle: "Everything you ate, by day",
              icon: "fork.knife", keywords: ["meals", "calories", "protein", "history", "log food"]),
        Entry(target: .mealPlan, group: .food, title: "Meal plan", subtitle: "Go-to meals for the week and a grocery list",
              icon: "calendar.day.timeline.left", keywords: ["groceries", "shopping", "prep"]),
        Entry(target: .eatingOut, group: .food, title: "Eating out", subtitle: "An order that fits what's left today",
              icon: "takeoutbag.and.cup.and.straw.fill", keywords: ["restaurant", "fast food", "chipotle"]),
        Entry(target: .scanBarcode, group: .food, title: "Scan barcode", subtitle: "Log packaged food by its barcode",
              icon: "barcode.viewfinder", keywords: ["scanner", "label"]),
        // Body
        Entry(target: .trendWeight, group: .body, title: "Trend weight", subtitle: "Your weight without the water swings",
              icon: "scalemass.fill", keywords: ["weight", "scale", "body fat", "lean mass", "wyze"]),
        Entry(target: .metabolism, group: .body, title: "Metabolism", subtitle: "How fast you burn, and your metabolic age",
              icon: "flame.fill", keywords: ["bmr", "rmr", "tdee", "metabolic age"]),
        Entry(target: .progressPhotos, group: .body, title: "Progress photos", subtitle: "Same pose, side by side",
              icon: "camera.fill", keywords: ["photo", "compare", "before after"]),
        Entry(target: .strength, group: .body, title: "Strength", subtitle: "Lifts vs weight, maxes and milestones",
              icon: "chart.line.uptrend.xyaxis", keywords: ["pr", "1rm", "bench", "squat"]),
        Entry(target: .sleep, group: .body, title: "Sleep", subtitle: "Score, tonight's bedtime and your week",
              icon: "moon.fill", keywords: ["bedtime", "rest", "score"]),
        Entry(target: .body, group: .body, title: "Body signals", subtitle: "Heart rate, HRV, recovery and illness watch",
              icon: "waveform.path.ecg", keywords: ["hrv", "resting heart rate", "readiness", "recovery"]),
        // Move
        Entry(target: .workoutPlan, group: .move, title: "Workout plan", subtitle: "This week's sessions and your logs",
              icon: "dumbbell.fill", keywords: ["gym", "lift", "training", "log workout"]),
        Entry(target: .mileHistory, group: .move, title: "Mile history", subtitle: "Your mile-a-day streak, day by day",
              icon: "figure.walk", keywords: ["streak", "walk", "run", "steps"]),
        Entry(target: .suggestedActivity, group: .move, title: "Suggested activity", subtitle: "Active stretches your heart rate caught",
              icon: "figure.mixed.cardio", keywords: ["heart rate", "pickleball", "earned calories"]),
        // Plan
        Entry(target: .schedule, group: .plan, title: "Schedule", subtitle: "Your week: wake-ups, events, workouts",
              icon: "calendar.badge.clock", keywords: ["agenda", "calendar", "events"]),
        Entry(target: .wakeUp, group: .plan, title: "Wake-up times & alarm", subtitle: "Usual times, one-day changes, missions",
              icon: "alarm.fill", keywords: ["alarm", "bedtime", "morning", "mission"]),
        Entry(target: .calendars, group: .plan, title: "Calendars", subtitle: "Connect Apple and Google calendars",
              icon: "calendar", keywords: ["google", "apple", "work"]),
        // Compete
        Entry(target: .challenge, group: .compete, title: "Challenge", subtitle: "You vs your friend, live",
              icon: "flag.2.crossed.fill", keywords: ["dave", "race", "leaderboard"]),
        Entry(target: .weeklyReport, group: .compete, title: "Weekly report", subtitle: "This week, head to head",
              icon: "doc.text.magnifyingglass", keywords: ["summary", "sunday"]),
        Entry(target: .sideBets, group: .compete, title: "Side bets", subtitle: "Weekly mini-battles and who owes what",
              icon: "dice.fill", keywords: ["bet", "wager", "stakes"]),
        Entry(target: .wrapped, group: .compete, title: "Dialed Wrapped", subtitle: "Your challenge as a story",
              icon: "gift.fill", keywords: ["recap", "story", "share"]),
        // Progress
        Entry(target: .badges, group: .progress, title: "Badges", subtitle: "Your trophy wall",
              icon: "trophy.fill", keywords: ["achievements", "awards", "levels", "quests"]),
        Entry(target: .habitHeatmap, group: .progress, title: "Habit heatmap", subtitle: "12 weeks of green squares",
              icon: "square.grid.3x3.fill", keywords: ["streaks", "consistency", "calendar"]),
        Entry(target: .weekInReview, group: .progress, title: "Week in review", subtitle: "How the week went, and patterns",
              icon: "calendar.badge.checkmark", keywords: ["patterns", "summary", "insights"]),
        Entry(target: .scoreCalendar, group: .progress, title: "Score calendar", subtitle: "Every day's Dialed score",
              icon: "calendar", keywords: ["history", "past days", "score"]),
        Entry(target: .timeline, group: .progress, title: "Day timeline", subtitle: "Everything you've logged today",
              icon: "clock.arrow.circlepath", keywords: ["today", "log", "history"]),
        // Setup
        Entry(target: .devices, group: .setup, title: "Devices & data", subtitle: "Watch, scale, bottle and a data check",
              icon: "dot.radiowaves.left.and.right", keywords: ["pixel", "wyze", "apple health", "google health", "sync"]),
        Entry(target: .customizeHome, group: .setup, title: "Customize Home", subtitle: "Reorder or hide Home's cards",
              icon: "slider.horizontal.3", keywords: ["layout", "cards", "order"]),
        Entry(target: .notifications, group: .setup, title: "Notifications", subtitle: "Reminders, nudges and alerts",
              icon: "bell.fill", keywords: ["alerts", "reminders", "push"]),
    ]

    /// Entries matching `query` (title, description and keywords; case and
    /// accents ignored; every word must match), grouped in a fixed order.
    /// An empty query returns everything.
    static func search(_ query: String, in entries: [Entry] = all) -> [Section] {
        let words = normalize(query).split(separator: " ").map(String.init)
        let matches = entries.filter { e in
            guard !words.isEmpty else { return true }
            let haystack = normalize(([e.title, e.subtitle, e.group.title] + e.keywords).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
        return Group.allCases.compactMap { g in
            let inGroup = matches.filter { $0.group == g }
            return inGroup.isEmpty ? nil : Section(group: g, entries: inGroup)
        }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
