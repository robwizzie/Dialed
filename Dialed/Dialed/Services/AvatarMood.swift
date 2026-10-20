//
//  AvatarMood.swift
//  Dialed
//
//  How today is going, as one of four moods your avatar takes on. The
//  score is time-aware: at 10 AM you're judged against where you should be
//  by 10 AM, not against the whole day. Moods show energy and attitude —
//  never body shape. Pure Foundation, unit-tested.
//

import Foundation

enum AvatarMood: String, CaseIterable, Codable, Identifiable {
    case onFire
    case lockedIn
    case gettingThere
    case runningOnEmpty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onFire:         return "On fire"
        case .lockedIn:       return "Locked in"
        case .gettingThere:   return "Getting there"
        case .runningOnEmpty: return "Running on empty"
        }
    }

    var emoji: String {
        switch self {
        case .onFire:         return "🔥"
        case .lockedIn:       return "💪"
        case .gettingThere:   return "🚶"
        case .runningOnEmpty: return "😴"
        }
    }

    var tagline: String {
        switch self {
        case .onFire:         return "Everything's clicking. This is wedding-day you."
        case .lockedIn:       return "Solid day. Keep stacking these."
        case .gettingThere:   return "Room to push — one or two moves flips this."
        case .runningOnEmpty: return "Rough start. Small wins from here count."
        }
    }

    /// Accent as hex so this file stays UI-free.
    var accentHex: String {
        switch self {
        case .onFire:         return "F59A4C"
        case .lockedIn:       return "4CB868"
        case .gettingThere:   return "5DB4F0"
        case .runningOnEmpty: return "A88BEB"
        }
    }

    /// Image Playground prompt. Mood is carried by expression, outfit and
    /// setting only.
    var prompt: String {
        switch self {
        case .onFire:
            return "full of energy with a huge confident smile, bright athletic outfit, golden sunrise glow, celebrating a win"
        case .lockedIn:
            return "focused and determined, gym clothes, holding a water bottle, bright clean gym background"
        case .gettingThere:
            return "relaxed and steady, casual hoodie, out for a walk on a sunny sidewalk"
        case .runningOnEmpty:
            return "sleepy and low energy, yawning, cozy hoodie, holding a coffee mug by a rainy window"
        }
    }

    static func from(score: Int) -> AvatarMood {
        switch score {
        case 80...:  return .onFire
        case 60..<80: return .lockedIn
        case 40..<60: return .gettingThere
        default:      return .runningOnEmpty
        }
    }

    // MARK: - Scoring

    struct Component: Equatable {
        let name: String
        let points: Double
        let maxPoints: Double
        /// What to do to earn the missing points.
        let action: String

        var gap: Double { maxPoints - points }
    }

    struct Reading: Equatable {
        let score: Int
        let mood: AvatarMood
        let components: [Component]

        /// The two biggest gaps — "what would move you up".
        var boosts: [Component] {
            components.filter { $0.gap >= 3 }.sorted { $0.gap > $1.gap }.prefix(2).map { $0 }
        }
    }

    static func read(_ s: HealthSnapshot, calendar: Calendar = .current) -> Reading {
        let hour = Double(calendar.component(.hour, from: s.now)) + Double(calendar.component(.minute, from: s.now)) / 60
        // Fraction of the day's targets you "should" have by now (7 AM → 9 PM).
        let expected = max(0.15, min(1, (hour - 7) / 14))

        func paced(_ actual: Double, _ target: Double) -> Double {
            guard target > 0 else { return 1 }
            return max(0, min(1, actual / (target * expected)))
        }

        var parts: [Component] = []

        let water = paced(s.waterOz, s.waterTargetOz) * 20
        let waterGoalNow = Int((s.waterTargetOz * expected).rounded())
        parts.append(Component(name: "Water", points: water, maxPoints: 20,
                               action: "Drink up to \(waterGoalNow) oz"))

        let steps = paced(Double(s.steps), Double(s.stepGoal)) * 10
        parts.append(Component(name: "Steps", points: steps, maxPoints: 10,
                               action: "Take a walk"))

        // The daily mile, walked or run: full marks once it's done.
        let miles = s.miles ?? MileADay.miles(distance: nil, steps: s.steps)
        let mile = MileADay.isDone(miles) ? 10 : paced(miles, MileADay.goal) * 10
        parts.append(Component(name: "Mile", points: mile, maxPoints: 10,
                               action: "Get your mile in — about \(Int(((MileADay.goal - min(miles, MileADay.goal)) * 20).rounded())) min of walking"))

        let protein = paced(s.proteinGrams, s.proteinTarget) * 20
        parts.append(Component(name: "Protein", points: protein, maxPoints: 20,
                               action: "Have a protein-heavy meal or shake"))

        var budget = 15.0
        if s.calorieTarget > 0, s.caloriesIn > s.calorieTarget {
            budget = max(0, 15 - (s.caloriesIn - s.calorieTarget) / s.calorieTarget * 60)
        }
        parts.append(Component(name: "Calorie budget", points: budget, maxPoints: 15,
                               action: "Keep the rest of today light"))

        let sleep: Double
        switch s.sleepHours {
        case nil:              sleep = 10
        case let h? where h >= 7: sleep = 15
        case let h? where h >= 6: sleep = 10
        default:               sleep = 4
        }
        parts.append(Component(name: "Sleep", points: sleep, maxPoints: 15,
                               action: "Lights out by 10:30 tonight"))

        let weighIn: Double = s.weighedInToday ? 10 : (hour < 12 ? 5 : 0)
        parts.append(Component(name: "Weigh-in", points: weighIn, maxPoints: 10,
                               action: "Step on the scale"))

        let total = Int(parts.reduce(0) { $0 + $1.points }.rounded())
        return Reading(score: total, mood: from(score: total), components: parts)
    }
}

// MARK: - Goal day

/// The day you're working toward (e.g. your brother's wedding).
struct GoalEvent: Codable, Equatable {
    var name: String
    var date: Date

    private static let key = "goalEvent.v1"
    static let didChangeNotification = Notification.Name("GoalEventDidChange")

    static func load(from defaults: UserDefaults = .standard) -> GoalEvent? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GoalEvent.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    func daysAway(from now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0)
    }
}
