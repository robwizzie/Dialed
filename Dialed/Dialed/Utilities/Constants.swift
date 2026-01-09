//
//  Constants.swift
//  Dialed
//
//  App-wide constants
//

import Foundation

struct Constants {
    // Day cutoff (4 AM - items before this count for previous day)
    static let dayCutoffHour = 4

    // Scoring weights (total = 100 points)
    struct Scoring {
        static let proteinWeight = 25
        static let workoutCompletionWeight = 10
        static let workoutQualityWeight = 10
        static let mileCompletionWeight = 7
        static let mileQualityWeight = 8
        static let sleepWeight = 20
        static let hydrationWeight = 10
        static let routineWeight = 10
    }

    // Score thresholds
    struct ScoreThresholds {
        static let elite = 90
        static let strong = 75
        static let decent = 60
        static let slipping = 40
    }

    // Sleep score targets (for automated calculation)
    struct Sleep {
        static let optimalDurationMin = 7.0  // hours
        static let optimalDurationMax = 9.0  // hours
        static let optimalEfficiency = 0.85  // 85%
        static let optimalDeepSleepMin = 0.15  // 15% of total
        static let optimalDeepSleepMax = 0.25  // 25% of total
        static let goodHRVThreshold = 50.0  // milliseconds
    }

    // Red flag thresholds
    struct RedFlags {
        static let lowSleepScoreThreshold = 2.0
        static let lowWorkoutScoreThreshold = 2.0
        static let lowProteinGrams = 150.0
        static let lowWaterPercentage = 0.70
        static let daysToCheck = 3
        static let mileMissedDaysInWeek = 2
    }

    // Checklist item types
    enum ChecklistType: String, Codable, CaseIterable {
        case amSkincare = "AM Skincare"
        case lunchVitamins = "Lunch Vitamins"
        case creatine = "Creatine"
        case postWorkoutLog = "Post-Workout Log"
        case closeTheDay = "Close the Day"
        case pmSkincare = "PM Skincare"

        var defaultTime: DateComponents {
            switch self {
            case .amSkincare:
                return DateComponents(hour: 8, minute: 40)
            case .lunchVitamins:
                return DateComponents(hour: 12, minute: 0)
            case .creatine:
                return DateComponents(hour: 17, minute: 15)
            case .postWorkoutLog:
                return DateComponents(hour: 19, minute: 45)
            case .closeTheDay:
                return DateComponents(hour: 20, minute: 30)
            case .pmSkincare:
                return DateComponents(hour: 23, minute: 0)
            }
        }

        var description: String {
            switch self {
            case .amSkincare:
                return "Rinse face + apply CeraVe AM"
            case .lunchVitamins:
                return "Fish oil + Vitamin D3/K2"
            case .creatine:
                return "Animal creatine chews"
            case .postWorkoutLog:
                return "Log workout, tag type, rate quality"
            case .closeTheDay:
                return "Confirm workout + mile + protein + water"
            case .pmSkincare:
                return "Wash face + apply CeraVe PM"
            }
        }

        var countsForPoints: Bool {
            switch self {
            case .postWorkoutLog, .closeTheDay:
                return false  // These are reminders only, not scored
            default:
                return true
            }
        }
    }

    // Workout tags
    enum WorkoutTag: String, Codable, CaseIterable {
        case pull = "Pull (Back/Bis)"
        case push = "Push (Chest/Shoulders)"
        case legs = "Legs"
        case armsCore = "Arms+Core"
        case upperPump = "Upper Pump"
        case rest = "Rest"

        var shortName: String {
            switch self {
            case .pull:
                return "Pull"
            case .push:
                return "Push"
            case .legs:
                return "Legs"
            case .armsCore:
                return "Arms+Core"
            case .upperPump:
                return "Upper Pump"
            case .rest:
                return "Rest"
            }
        }
    }
}
