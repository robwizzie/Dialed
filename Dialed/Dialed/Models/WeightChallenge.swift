//
//  WeightChallenge.swift
//  Dialed
//
//  The head-to-head weight-loss challenge: who loses more in a fixed
//  window. Stored in UserDefaults as JSON (one active challenge at a time,
//  same pattern as UserSettings). The friend's numbers are entered by hand
//  since they live in someone else's app.
//

import Foundation

struct WeightChallenge: Codable, Equatable {
    static let didChangeNotification = Notification.Name("WeightChallengeDidChange")

    var friendName: String
    var startDate: Date
    var endDate: Date

    /// Your starting weight in lbs. nil = use the first reading on or after
    /// `startDate` (falling back to the last one before it).
    var startWeightOverride: Double?

    /// Personal target for the window, lbs.
    var goalLossLbs: Double

    /// The friend's starting weight. nil = their first logged weigh-in.
    var friendStartWeight: Double?
    var friendWeighIns: [FriendWeighIn]

    /// How the winner is decided. Percent is the fair default when the two
    /// of you start at different weights.
    var scoring: Scoring

    struct FriendWeighIn: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var date: Date
        var pounds: Double
    }

    enum Scoring: String, Codable, CaseIterable, Identifiable {
        case percent
        case pounds

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .percent: return "% of body weight"
            case .pounds:  return "Total lbs"
            }
        }
    }

    // MARK: - Defaults

    /// A one-month challenge starting today.
    static func makeDefault(now: Date = Date(), calendar: Calendar = .current) -> WeightChallenge {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(30 * 86_400)
        return WeightChallenge(
            friendName: "",
            startDate: start,
            endDate: end,
            startWeightOverride: nil,
            goalLossLbs: 8,
            friendStartWeight: nil,
            friendWeighIns: [],
            scoring: .percent
        )
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "weightChallenge.v1"

    static func load(from defaults: UserDefaults = .standard) -> WeightChallenge? {
        guard let data = defaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(WeightChallenge.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    var friendDisplayName: String {
        friendName.trimmingCharacters(in: .whitespaces).ifEmpty("Your friend")
    }
}
