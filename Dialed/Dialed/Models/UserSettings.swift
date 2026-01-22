//
//  UserSettings.swift
//  Dialed
//
//  User preferences and targets (stored in UserDefaults)
//

import Foundation

// MARK: - Scheduled Time (Simple time storage)
struct ScheduledTime: Codable, Hashable {
    var hour: Int
    var minute: Int
    
    var asDateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }
    
    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
    
    init(from dateComponents: DateComponents) {
        self.hour = dateComponents.hour ?? 0
        self.minute = dateComponents.minute ?? 0
    }
}

struct UserSettings: Codable {
    // Personal metrics
    var currentWeight: Double  // lbs
    var height: Double  // inches
    var goalWeight: Double  // lbs

    // Daily targets
    var proteinTargetGrams: Double
    var waterTargetOz: Double
    var calorieTarget: Double?  // Optional

    // Workout expectations
    var expectedWorkoutsPerWeek: Int

    // Notification preferences
    var notificationsEnabled: Bool
    var enabledNotifications: Set<String>  // ChecklistType raw values

    // HealthKit integration
    var healthKitEnabled: Bool

    // Customizable checklist times (if user wants to override defaults)
    var customChecklistTimes: [String: ScheduledTime]?  // ChecklistType.rawValue: time

    static let defaultSettings = UserSettings(
        currentWeight: 190,
        height: 72,  // 6'0"
        goalWeight: 185,
        proteinTargetGrams: 190,
        waterTargetOz: 120,
        calorieTarget: nil,
        expectedWorkoutsPerWeek: 6,
        notificationsEnabled: true,
        enabledNotifications: Set(Constants.ChecklistType.allCases.map { $0.rawValue }),
        healthKitEnabled: false,
        customChecklistTimes: nil
    )

    // UserDefaults key
    private static let userDefaultsKey = "userSettings"

    // Save to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    // Load from UserDefaults
    static func load() -> UserSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            return defaultSettings
        }
        return settings
    }

    // Calculate protein target from goal weight (0.85g per lb)
    static func calculateProteinTarget(goalWeight: Double) -> Double {
        return goalWeight * 0.85
    }

    // Calculate water target from current weight (half body weight in oz)
    static func calculateWaterTarget(currentWeight: Double) -> Double {
        return currentWeight / 2.0
    }
}
