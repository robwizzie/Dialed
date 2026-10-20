//
//  WidgetBridge.swift
//  Dialed (app + DialedWidgets)
//
//  The handshake between the app and its widgets, through the shared
//  App Group's UserDefaults. The app writes a small snapshot of today
//  (water, protein, calories, favorite meals); the widget only reads it.
//  Widget buttons can't touch the app's SwiftData store, so a tap appends
//  to a pending queue instead — the widget shows it right away on top of
//  the snapshot, and the app logs it properly the next time it runs.
//
//  Foundation only: this file is compiled into both targets.
//

import Foundation

struct WidgetFavorite: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var calories: Double
    var protein: Double
}

/// A meal logged today, for the Fuel widget's "today's plate".
struct WidgetMeal: Codable, Equatable {
    var name: String
    var calories: Double
    var protein: Double
    var time: Date
}

struct WidgetSnapshot: Codable, Equatable {
    var waterOz: Double
    var waterTargetOz: Double
    var protein: Double
    var proteinTarget: Double
    var calories: Double
    var calorieTarget: Double
    var favorites: [WidgetFavorite]
    var updatedAt: Date
    /// Today's meals, oldest first. Optional so v1 snapshots still decode.
    var meals: [WidgetMeal]? = nil

    var waterProgress: Double { waterTargetOz > 0 ? min(1, waterOz / waterTargetOz) : 0 }
    var proteinProgress: Double { proteinTarget > 0 ? min(1, protein / proteinTarget) : 0 }
    var calorieProgress: Double { calorieTarget > 0 ? min(1, calories / calorieTarget) : 0 }
    var waterLeftOz: Double { max(0, waterTargetOz - waterOz) }
    var proteinLeft: Double { max(0, proteinTarget - protein) }
    var caloriesLeft: Double { calorieTarget - calories }
    var dialedScore: Int { dialedScore(miles: nil) }

    /// The Dialed score, with today's mile when Home has published it.
    func dialedScore(miles: Double?) -> Int {
        DialedScore.compute(waterOz: waterOz, waterTargetOz: waterTargetOz, protein: protein,
                            proteinTarget: proteinTarget, calories: calories, calorieTarget: calorieTarget,
                            miles: miles)
    }

    /// Shown before the app has written anything (and in the gallery).
    static let placeholder = WidgetSnapshot(
        waterOz: 64, waterTargetOz: 120,
        protein: 110, proteinTarget: 190,
        calories: 1_250, calorieTarget: 2_200,
        favorites: [
            WidgetFavorite(id: UUID(), name: "Clear Whey Shake", calories: 90, protein: 20),
            WidgetFavorite(id: UUID(), name: "Greek Yogurt Bowl", calories: 320, protein: 28),
            WidgetFavorite(id: UUID(), name: "Chicken Rice Bowl", calories: 610, protein: 52),
            WidgetFavorite(id: UUID(), name: "Egg Wrap", calories: 380, protein: 30)
        ],
        updatedAt: Date(),
        meals: [
            WidgetMeal(name: "Egg Wrap", calories: 380, protein: 30, time: Date().addingTimeInterval(-5 * 3600)),
            WidgetMeal(name: "Chicken Rice Bowl", calories: 610, protein: 52, time: Date().addingTimeInterval(-2 * 3600)),
            WidgetMeal(name: "Clear Whey Shake", calories: 90, protein: 20, time: Date().addingTimeInterval(-1800))
        ]
    )

    /// The numbers to show at `now`: zeroed after the day rolls over (the
    /// app hasn't refreshed yet), plus any widget taps still waiting in the
    /// queue for today.
    func display(with pending: [PendingLog], now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        var out = self
        let today = WidgetBridge.logicalDay(for: now, calendar: calendar)
        if WidgetBridge.logicalDay(for: updatedAt, calendar: calendar) != today {
            out.waterOz = 0
            out.protein = 0
            out.calories = 0
            out.meals = []
        }
        for log in pending.sorted(by: { $0.date < $1.date })
        where WidgetBridge.logicalDay(for: log.date, calendar: calendar) == today {
            switch log.kind {
            case .water:
                out.waterOz += log.amount ?? 0
            case .favorite:
                if let meal = favorites.first(where: { $0.id == log.favoriteID }) {
                    out.calories += meal.calories
                    out.protein += meal.protein
                    out.meals = (out.meals ?? []) + [
                        WidgetMeal(name: meal.name, calories: meal.calories, protein: meal.protein, time: log.date)
                    ]
                }
            }
        }
        return out
    }
}

// MARK: - Insights

/// The rest of today, published by Home after each refresh: activity,
/// recovery, weight, the day score and the challenge. Everything is
/// optional — a missing device just leaves that widget tile empty.
struct WidgetInsights: Codable, Equatable {
    struct Score: Codable, Equatable {
        struct Part: Codable, Equatable {
            var name: String
            var points: Double
            var maxPoints: Double
            var progress: Double { maxPoints > 0 ? max(0, min(1, points / maxPoints)) : 0 }
        }

        var value: Int
        /// AvatarMood raw value ("onFire", "lockedIn", …).
        var mood: String
        var title: String
        var emoji: String
        var tagline: String
        var accentHex: String
        var parts: [Part]
        /// The biggest thing that would move the score up right now.
        var boost: String?
    }

    struct Challenge: Codable, Equatable {
        var friendName: String
        var scoresPercent: Bool
        var youLost: Double
        var friendLost: Double?
        /// "you", "friend", "tied" or "unknown".
        var leader: String
        /// Lead in the scoring unit (lbs or %), always ≥ 0.
        var margin: Double
        var dayNumber: Int
        var totalDays: Int
        var daysLeft: Int
        var goalLossLbs: Double
        var lostLbs: Double
        var weighedInToday: Bool
        var weighInStreak: Int
        /// The race (RacePace): lbs/week needed to finish ahead, your pace,
        /// and "ahead" / "onTrack" / "behind" / "unknown". Optional so older
        /// insights decode.
        var neededPace: Double? = nil
        var yourPace: Double? = nil
        var raceStatus: String? = nil

        /// The last 14 days: final push.
        var isFinalPush: Bool { daysLeft <= 14 }

        var goalProgress: Double { goalLossLbs > 0 ? max(0, min(1, lostLbs / goalLossLbs)) : 0 }
        var timeProgress: Double { totalDays > 0 ? max(0, min(1, Double(dayNumber) / Double(totalDays))) : 0 }
    }

    struct Goal: Codable, Equatable {
        var name: String
        var date: Date
        /// Projected weight that day if the current trend holds.
        var projectedWeight: Double?
    }

    var steps: Int
    var stepGoal: Int
    /// Last seven days, oldest first; the last value is today.
    var stepsWeek: [Int]
    var waterWeek: [Double]
    var sleepHours: Double?
    var sleepWeek: [Double]
    var hrv: Double?
    var hrvBaseline: Double?
    var restingHR: Double?
    var weight: Double?
    /// Daily weights (oldest first) for the sparkline.
    var weightTrend: [Double]
    var score: Score?
    var challenge: Challenge?
    var goal: Goal?
    var updatedAt: Date
    /// The daily mile (walked or run). Optional so older insights decode.
    var miles: Double? = nil
    var mileStreak: Int? = nil

    var stepProgress: Double { stepGoal > 0 ? min(1, Double(steps) / Double(stepGoal)) : 0 }

    /// Weight change across the sparkline (negative = down).
    var weightChange: Double? {
        guard let first = weightTrend.first, let last = weightTrend.last, weightTrend.count > 1 else { return nil }
        return last - first
    }

    /// The numbers to show at `now`: today-only values (steps, the score)
    /// reset after the day rolls over and the app hasn't refreshed yet.
    func display(now: Date = Date(), calendar: Calendar = .current) -> WidgetInsights {
        guard WidgetBridge.logicalDay(for: updatedAt, calendar: calendar)
                != WidgetBridge.logicalDay(for: now, calendar: calendar) else { return self }
        var out = self
        out.steps = 0
        out.score = nil
        out.stepsWeek = Array((stepsWeek + [0]).suffix(7))
        out.waterWeek = Array((waterWeek + [0]).suffix(7))
        return out
    }

    static let placeholder = WidgetInsights(
        steps: 7_420, stepGoal: 10_000,
        stepsWeek: [8_200, 11_400, 6_100, 9_800, 12_300, 10_100, 7_420],
        waterWeek: [96, 120, 88, 132, 110, 124, 64],
        sleepHours: 7.4, sleepWeek: [6.8, 7.1, 6.2, 7.9, 8.1, 6.9, 7.4],
        hrv: 52, hrvBaseline: 47, restingHR: 56,
        weight: 186.4,
        weightTrend: [191.2, 190.8, 190.1, 189.9, 189.0, 188.6, 188.1, 187.7, 187.4, 186.9, 186.4],
        score: Score(
            value: 74, mood: "lockedIn", title: "Locked in", emoji: "💪",
            tagline: "Solid day. Keep stacking these.", accentHex: "4CB868",
            parts: [
                .init(name: "Water", points: 15, maxPoints: 20),
                .init(name: "Steps", points: 7, maxPoints: 10),
                .init(name: "Mile", points: 7, maxPoints: 10),
                .init(name: "Protein", points: 13, maxPoints: 20),
                .init(name: "Calories", points: 15, maxPoints: 15),
                .init(name: "Sleep", points: 15, maxPoints: 15),
                .init(name: "Weigh-in", points: 2, maxPoints: 10)
            ],
            boost: "Have a protein-heavy meal or shake"
        ),
        challenge: Challenge(
            friendName: "Sam", scoresPercent: true, youLost: 2.5, friendLost: 1.9,
            leader: "you", margin: 0.6, dayNumber: 18, totalDays: 30, daysLeft: 12,
            goalLossLbs: 10, lostLbs: 4.8, weighedInToday: true, weighInStreak: 6,
            neededPace: 1.4, yourPace: 1.7, raceStatus: "onTrack"
        ),
        goal: Goal(name: "Wedding", date: Date().addingTimeInterval(41 * 86_400), projectedWeight: 181.0),
        updatedAt: Date()
    )
}

/// Where tapping a widget lands in the app: dialed://<rawValue>.
enum WidgetLink: String, CaseIterable {
    case home, water, meal, food, weighIn = "weigh-in", challenge, sleep, body, score

    static let scheme = "dialed"

    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host else { return nil }
        self.init(rawValue: host)
    }
}

/// A widget tap waiting for the app to log it.
struct PendingLog: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case water
        case favorite
    }

    var id: UUID
    var kind: Kind
    /// Ounces, for water.
    var amount: Double?
    /// The saved meal, for favorites.
    var favoriteID: UUID?
    var date: Date

    static func water(_ ounces: Double, at date: Date = Date()) -> PendingLog {
        PendingLog(id: UUID(), kind: .water, amount: ounces, favoriteID: nil, date: date)
    }

    static func favorite(_ id: UUID, at date: Date = Date()) -> PendingLog {
        PendingLog(id: UUID(), kind: .favorite, amount: nil, favoriteID: id, date: date)
    }
}

struct WidgetBridge {
    static let appGroupID = "group.org.robertwiscount.Dialed"
    static let widgetKind = "DialedTodayWidget"
    /// Matches the app's 4 AM day cutoff (Constants.dayCutoffHour).
    static let dayCutoffHour = 4

    static let snapshotKey = "widget.snapshot.v1"
    static let insightsKey = "widget.insights.v1"
    static let pendingKey = "widget.pending.v1"
    static let avatarFileName = "widget-avatar.jpg"
    static let processedKey = "widget.processed.v1"
    /// How many drained ids we remember for de-duplication.
    static let processedMemory = 200

    /// Nil when the App Group isn't provisioned; every call is then a no-op.
    let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: WidgetBridge.appGroupID)) {
        self.defaults = defaults
    }

    var isAvailable: Bool { defaults != nil }

    // MARK: - Snapshot

    func readSnapshot() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.snapshotKey) else { return nil }
        return try? Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    func writeSnapshot(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? Self.encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    // MARK: - Insights

    func readInsights() -> WidgetInsights? {
        guard let data = defaults?.data(forKey: Self.insightsKey) else { return nil }
        return try? Self.decoder.decode(WidgetInsights.self, from: data)
    }

    func writeInsights(_ insights: WidgetInsights) {
        guard let defaults, let data = try? Self.encoder.encode(insights) else { return }
        defaults.set(data, forKey: Self.insightsKey)
    }

    // MARK: - Avatar

    /// Today's mood avatar, as a small JPEG in the App Group container.
    static var avatarURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(avatarFileName)
    }

    /// Nil data removes the avatar (avatars turned off).
    static func writeAvatar(_ jpeg: Data?) {
        guard let url = avatarURL else { return }
        if let jpeg {
            try? jpeg.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Pending queue

    func pending() -> [PendingLog] {
        guard let data = defaults?.data(forKey: Self.pendingKey) else { return [] }
        return (try? Self.decoder.decode([PendingLog].self, from: data)) ?? []
    }

    func enqueue(_ log: PendingLog) {
        guard defaults != nil else { return }
        var queue = pending()
        guard !queue.contains(where: { $0.id == log.id }) else { return }
        queue.append(log)
        writePending(queue)
    }

    /// Takes the queued logs the app hasn't handled yet, oldest first, and
    /// removes them from the queue. Ids are remembered so a log that is
    /// re-delivered (e.g. a write that raced the drain) isn't logged twice.
    func drain() -> [PendingLog] {
        guard let defaults else { return [] }
        let queue = pending()
        guard !queue.isEmpty else { return [] }

        var processed = defaults.stringArray(forKey: Self.processedKey) ?? []
        var seen = Set(processed)
        var fresh: [PendingLog] = []
        for log in queue.sorted(by: { $0.date < $1.date }) where !seen.contains(log.id.uuidString) {
            seen.insert(log.id.uuidString)
            fresh.append(log)
            processed.append(log.id.uuidString)
        }
        defaults.set(Array(processed.suffix(Self.processedMemory)), forKey: Self.processedKey)

        // Re-read so a tap that landed meanwhile stays queued.
        let drained = Set(queue.map(\.id))
        writePending(pending().filter { !drained.contains($0.id) })
        return fresh
    }

    private func writePending(_ queue: [PendingLog]) {
        guard let defaults, let data = try? Self.encoder.encode(queue) else { return }
        defaults.set(data, forKey: Self.pendingKey)
    }

    // MARK: - Helpers

    /// Start of the "app day" (before 4 AM counts as the previous day).
    static func logicalDay(for date: Date, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < dayCutoffHour else { return base }
        return calendar.date(byAdding: .day, value: -1, to: base) ?? base
    }

    // Default date strategy (reference-date seconds) round-trips exactly.
    private static var encoder: JSONEncoder { JSONEncoder() }
    private static var decoder: JSONDecoder { JSONDecoder() }
}
