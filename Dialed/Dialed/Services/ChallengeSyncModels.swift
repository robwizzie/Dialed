//
//  ChallengeSyncModels.swift
//  Dialed
//
//  Wire format for the live challenge server (challenge-worker/ in the
//  repo) and the pure mapping between it and the local WeightChallenge.
//  Dates travel as local "yyyy-MM-dd" day keys. Pure Foundation, tested.
//

import Foundation

enum ChallengeWire {
    struct CreateRequest: Encodable {
        let ownerName: String
        let friendName: String
        let startDate: String
        let endDate: String
        let ownerStart: Double?
        let friendStart: Double?
    }

    struct CreateResponse: Decodable {
        let id: String
        let ownerToken: String
        let friendToken: String
        let inviteUrl: String
    }

    struct State: Decodable, Equatable {
        let role: String
        let challenge: Challenge
        let weighins: [WeighIn]
        let messages: [Message]
        /// Each side's stats card, keyed "owner" / "friend".
        var stats: [String: SideStats]?
    }

    /// Optional, loosely-typed stats a side shares (all fields optional).
    struct SideStats: Decodable, Equatable {
        var goalLossLbs: Double?
        var stepsAvg7: Double?
        var stepsToday: Double?
        var stepsDate: String?
        var workoutsWeek: Double?
        var workoutsTotal: Double?
        var goalDayName: String?
        var updatedAt: String?
    }

    struct Challenge: Decodable, Equatable {
        let id: String
        let ownerName: String
        let friendName: String
        let startDate: String
        let endDate: String
        let ownerStart: Double?
        let friendStart: Double?
    }

    struct WeighIn: Codable, Equatable {
        var role: String?
        let date: String
        let pounds: Double
        /// "scale" when it came in automatically from their scale.
        var source: String?
        var updatedAt: String?

        init(role: String?, date: String, pounds: Double, source: String? = nil, updatedAt: String? = nil) {
            self.role = role
            self.date = date
            self.pounds = pounds
            self.source = source
            self.updatedAt = updatedAt
        }
    }

    /// What we show about the other side in the app.
    struct OtherSide: Equatable {
        let name: String
        let lastDate: Date?
        let lastPounds: Double?
        let lastFromScale: Bool
        let lastUpdated: Date?
        let autoSync: Bool
        /// Positive = losing, lb per week, from the last 21 days.
        let weeklyLoss: Double?
        /// Projected total lost by the end date at that pace.
        let projectedLoss: Double?
        let streak: Int
        let stats: SideStats?
    }

    static func otherSide(_ state: State, now: Date = Date(), calendar: Calendar = .current) -> OtherSide {
        let other = state.role == "owner" ? "friend" : "owner"
        let name = other == "owner" ? state.challenge.ownerName : state.challenge.friendName
        let series = state.weighins.filter { $0.role == other }.sorted { $0.date < $1.date }
        let dated = series.compactMap { w in date(fromKey: w.date, calendar: calendar).map { ($0, w.pounds) } }
        let start = (other == "owner" ? state.challenge.ownerStart : state.challenge.friendStart) ?? dated.first?.1
        let last = series.last

        // Least-squares slope over the last 21 days, clamped to ±3 lb/week.
        let since = calendar.date(byAdding: .day, value: -21, to: calendar.startOfDay(for: now)) ?? now
        let recent = dated.filter { $0.0 >= since }
        var slopePerDay: Double?
        if recent.count >= 2 {
            let xs = recent.map { $0.0.timeIntervalSince1970 / 86_400 }, ys = recent.map(\.1)
            let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
            let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
            if den > 0 {
                let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
                slopePerDay = max(-3.0 / 7, min(3.0 / 7, num / den))
            }
        }
        var projected: Double?
        if let slope = slopePerDay, let current = last?.pounds, let start,
           let end = date(fromKey: state.challenge.endDate, calendar: calendar) {
            let daysLeft = max(0, Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0))
            projected = start - (current + slope * daysLeft)
        }

        // Consecutive days with a weigh-in, ending today or yesterday.
        let keys = Set(series.map(\.date))
        var day = calendar.startOfDay(for: now)
        if !keys.contains(dayKey(day, calendar: calendar)) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var streak = 0
        while keys.contains(dayKey(day, calendar: calendar)) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return OtherSide(
            name: name,
            lastDate: last.flatMap { date(fromKey: $0.date, calendar: calendar) },
            lastPounds: last?.pounds,
            lastFromScale: last?.source == "scale",
            lastUpdated: last?.updatedAt.flatMap { iso.date(from: $0) },
            autoSync: series.contains { $0.source == "scale" },
            weeklyLoss: slopePerDay.map { -$0 * 7 },
            projectedLoss: projected,
            streak: streak,
            stats: state.stats?[other])
    }

    struct Message: Decodable, Equatable, Identifiable {
        let id: Int
        let role: String
        let text: String
        let createdAt: String
    }

    struct WeighInBatch: Encodable {
        let weighins: [WeighIn]
        var source: String = "app"
    }

    /// Your stats card on the shared page (what your friend sees).
    struct OwnerStats: Encodable, Equatable {
        var goalLossLbs: Double?
        var scoring: String?
        var stepsAvg7: Double?
        var stepsToday: Double?
        var workoutsWeek: Int?
        var workoutsTotal: Int?
        var goalDayName: String?
        var goalDayDate: String?
    }

    /// Workouts done this week (Mon–Sun) and in total, from "yyyy-MM-dd" keys.
    static func workoutCounts(doneDays: [String], now: Date = Date(), calendar: Calendar = .current) -> (week: Int, total: Int) {
        var cal = calendar
        cal.firstWeekday = 2
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let week = Set(doneDays).compactMap { date(fromKey: $0, calendar: calendar) }.filter { $0 >= weekStart && $0 <= now }.count
        return (week, Set(doneDays).count)
    }

    // MARK: - Day keys

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: - Mapping

    /// Your weigh-ins to upload: the last reading of each day inside the
    /// challenge window.
    static func uploads(from readings: [(date: Date, pounds: Double)], start: Date, end: Date,
                        calendar: Calendar = .current) -> [WeighIn] {
        let from = calendar.startOfDay(for: start)
        let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        var byDay: [String: (Date, Double)] = [:]
        for r in readings where r.date >= from && r.date < to {
            let key = dayKey(r.date, calendar: calendar)
            if let existing = byDay[key], existing.0 > r.date { continue }
            byDay[key] = (r.date, r.pounds)
        }
        return byDay.keys.sorted().map { WeighIn(role: nil, date: $0, pounds: (byDay[$0]!.1 * 10).rounded() / 10) }
    }

    /// The other side's weigh-ins as local friend weigh-ins (noon on the day).
    static func friendWeighIns(from state: State, calendar: Calendar = .current) -> [WeightChallenge.FriendWeighIn] {
        let other = state.role == "owner" ? "friend" : "owner"
        return state.weighins
            .filter { $0.role == other }
            .compactMap { w in
                guard let day = date(fromKey: w.date, calendar: calendar),
                      let noon = calendar.date(byAdding: .hour, value: 12, to: day) else { return nil }
                return WeightChallenge.FriendWeighIn(date: noon, pounds: w.pounds)
            }
            .sorted { $0.date < $1.date }
    }

    /// Apply the server's view of the friend to the local challenge.
    static func merge(_ state: State, into challenge: WeightChallenge, calendar: Calendar = .current) -> WeightChallenge {
        var c = challenge
        // Keep local ids for unchanged weigh-ins so a repeat sync is a no-op.
        let remote = friendWeighIns(from: state, calendar: calendar).map { w -> WeightChallenge.FriendWeighIn in
            var w = w
            if let same = challenge.friendWeighIns.first(where: { $0.date == w.date && $0.pounds == w.pounds }) { w.id = same.id }
            return w
        }
        if !remote.isEmpty { c.friendWeighIns = remote }
        let friendStart = state.role == "owner" ? state.challenge.friendStart : state.challenge.ownerStart
        if let friendStart { c.friendStartWeight = friendStart }
        else if c.friendStartWeight == nil { c.friendStartWeight = remote.first?.pounds }
        return c
    }
}
