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
    }

    struct Message: Decodable, Equatable, Identifiable {
        let id: Int
        let role: String
        let text: String
        let createdAt: String
    }

    struct WeighInBatch: Encodable {
        let weighins: [WeighIn]
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
