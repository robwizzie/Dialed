//
//  TrackingPreferences.swift
//  Dialed
//
//  User preferences for what categories to track
//

import Foundation

struct TrackingPreferences: Codable {
    var trackSleep: Bool = true           // 20 points base
    var trackWorkout: Bool = true         // 20 points (10 completion + 10 quality)
    var trackMile: Bool = true            // 15 points (7 completion + 8 quality)
    var trackWater: Bool = true           // 10 points
    var trackProtein: Bool = true         // 27 points (25 + 2 bonus)
    var trackChecklist: Bool = true       // 10 points (dynamically distributed)

    // MARK: - Persistence

    private static let userDefaultsKey = "trackingPreferences"

    static func load() -> TrackingPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? JSONDecoder().decode(TrackingPreferences.self, from: data) else {
            return TrackingPreferences()
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: TrackingPreferences.userDefaultsKey)
        }
    }

    // MARK: - Scoring Calculation

    /// Calculate total base points from enabled categories
    var totalBasePoints: Double {
        var total: Double = 0

        if trackSleep { total += 20 }           // Sleep
        if trackWorkout { total += 20 }         // Workout (10 + 10)
        if trackMile { total += 15 }            // Mile (7 + 8)
        if trackWater { total += 10 }           // Water
        if trackProtein { total += 27 }         // Protein (25 + 2 bonus)
        if trackChecklist { total += 10 }       // Checklist

        return total
    }

    /// Calculate scale factor to normalize to 100 points
    /// This redistributes points proportionally among enabled categories
    var scaleFactor: Double {
        guard totalBasePoints > 0 else { return 1.0 }
        return 100.0 / totalBasePoints
    }

    /// Get adjusted points for a category (scaled to 100)
    func adjustedPoints(for basePoints: Double) -> Double {
        return basePoints * scaleFactor
    }

    /// Summary of what's being tracked
    var trackingSummary: String {
        let categories = [
            trackSleep ? "Sleep" : nil,
            trackWorkout ? "Workouts" : nil,
            trackMile ? "Mile" : nil,
            trackWater ? "Water" : nil,
            trackProtein ? "Protein" : nil,
            trackChecklist ? "Routine" : nil
        ].compactMap { $0 }

        if categories.isEmpty {
            return "Nothing tracked"
        } else if categories.count == 6 {
            return "All categories"
        } else {
            return categories.joined(separator: ", ")
        }
    }

    /// Number of enabled categories
    var enabledCount: Int {
        var count = 0
        if trackSleep { count += 1 }
        if trackWorkout { count += 1 }
        if trackMile { count += 1 }
        if trackWater { count += 1 }
        if trackProtein { count += 1 }
        if trackChecklist { count += 1 }
        return count
    }

    /// Check if at least one category is enabled
    var hasAnyEnabled: Bool {
        return trackSleep || trackWorkout || trackMile || trackWater || trackProtein || trackChecklist
    }
}

// MARK: - Category Info

extension TrackingPreferences {
    struct CategoryInfo {
        let name: String
        let description: String
        let basePoints: Double
        let icon: String
        let gradientColors: [String] // Color names for gradient
    }

    static let categories: [(keyPath: WritableKeyPath<TrackingPreferences, Bool>, info: CategoryInfo)] = [
        (
            \.trackSleep,
            CategoryInfo(
                name: "Sleep",
                description: "Track sleep quality and duration",
                basePoints: 20,
                icon: "bed.double.fill",
                gradientColors: ["indigo", "purple"]
            )
        ),
        (
            \.trackWorkout,
            CategoryInfo(
                name: "Workouts",
                description: "Log exercises and track progress",
                basePoints: 20,
                icon: "figure.strengthtraining.traditional",
                gradientColors: ["green", "mint"]
            )
        ),
        (
            \.trackMile,
            CategoryInfo(
                name: "Mile Run",
                description: "Track daily mile completion",
                basePoints: 15,
                icon: "figure.run",
                gradientColors: ["orange", "red"]
            )
        ),
        (
            \.trackWater,
            CategoryInfo(
                name: "Hydration",
                description: "Monitor daily water intake",
                basePoints: 10,
                icon: "drop.fill",
                gradientColors: ["blue", "cyan"]
            )
        ),
        (
            \.trackProtein,
            CategoryInfo(
                name: "Protein",
                description: "Track protein consumption",
                basePoints: 27,
                icon: "fork.knife",
                gradientColors: ["orange", "red"]
            )
        ),
        (
            \.trackChecklist,
            CategoryInfo(
                name: "Daily Routine",
                description: "Complete daily checklist tasks",
                basePoints: 10,
                icon: "checklist",
                gradientColors: ["orange", "yellow"]
            )
        )
    ]
}
