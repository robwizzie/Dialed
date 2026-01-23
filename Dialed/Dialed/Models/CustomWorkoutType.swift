//
//  CustomWorkoutType.swift
//  Dialed
//
//  User-defined workout types
//

import Foundation
import SwiftData

@Model
final class CustomWorkoutType {
    var id: UUID
    var name: String
    var shortName: String
    var icon: String  // SF Symbol name
    var colorHex: String  // For UI customization
    var createdAt: Date
    var isEnabled: Bool  // Whether to track this type

    init(
        name: String,
        shortName: String,
        icon: String = "dumbbell.fill",
        colorHex: String = "#00C853",
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.shortName = shortName
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.isEnabled = isEnabled
    }
}

// Workout Type Preferences (stored in UserDefaults)
struct WorkoutTypePreferences: Codable {
    // Built-in types that are enabled
    var enabledBuiltInTypes: Set<String>  // WorkoutTag rawValues

    // HKWorkoutActivityType mapping preferences
    var trackOnlyTraditionalStrength: Bool

    static let didChangeNotification = Notification.Name("WorkoutTypePreferencesDidChange")

    static let defaultPreferences = WorkoutTypePreferences(
        enabledBuiltInTypes: Set(Constants.WorkoutTag.allCases.map { $0.rawValue }),
        trackOnlyTraditionalStrength: true  // Default: only track traditional strength
    )

    private static let userDefaultsKey = "workoutTypePreferences"

    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    static func load() -> WorkoutTypePreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? JSONDecoder().decode(WorkoutTypePreferences.self, from: data) else {
            return defaultPreferences
        }
        return prefs
    }
}
