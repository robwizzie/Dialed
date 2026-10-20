//
//  HeadToHead.swift
//  Dialed
//
//  What to say when the live challenge changes on its own: "Dave just
//  weighed in" framed by the scoreboard (who leads, by how much, in the
//  challenge's scoring), and when an occasional trash-talk nudge is
//  earned (a lead change, a big drop, a weigh-in streak) and allowed
//  (two a week at most, never overnight). Only uses what the Challenge tab
//  already shows. Pure Foundation, tested.
//

import Foundation

enum HeadToHead {

    /// What we last told you about, so the next sync can tell what changed.
    struct Snapshot: Codable, Equatable {
        /// "you" / "friend" / "tied" / "unknown"
        var leader: String
        /// Friend weigh-ins already announced, as "yyyy-MM-dd@pounds".
        var friendKeys: [String]
        var yourStreak: Int
    }

    struct Alert: Equatable {
        var title: String
        var body: String
    }

    enum NudgeReason: Equatable {
        case tookLead
        case lostLead
        case friendBigDrop
        case streak(Int)
    }

    // MARK: - Snapshot

    static func leaderKey(_ leader: WeightChallengeEngine.Leader) -> String {
        switch leader {
        case .you:     return "you"
        case .friend:  return "friend"
        case .tied:    return "tied"
        case .unknown: return "unknown"
        }
    }

    static func key(_ w: WeightChallenge.FriendWeighIn, calendar: Calendar = .current) -> String {
        "\(ChallengeWire.dayKey(w.date, calendar: calendar))@\(String(format: "%.1f", w.pounds))"
    }

    static func snapshot(_ p: WeightChallengeEngine.Progress, friendWeighIns: [WeightChallenge.FriendWeighIn],
                         calendar: Calendar = .current) -> Snapshot {
        Snapshot(leader: leaderKey(p.leader), friendKeys: friendWeighIns.map { key($0, calendar: calendar) },
                 yourStreak: p.weighInStreak)
    }

    /// Friend weigh-ins that weren't there last time, oldest first.
    static func newWeighIns(_ weighIns: [WeightChallenge.FriendWeighIn], since old: Snapshot?,
                            calendar: Calendar = .current) -> [WeightChallenge.FriendWeighIn] {
        guard let old else { return [] }   // first look: nothing is "new"
        let seen = Set(old.friendKeys)
        return weighIns.filter { !seen.contains(key($0, calendar: calendar)) }.sorted { $0.date < $1.date }
    }

    // MARK: - "Dave just weighed in"

    static func margin(_ value: Double, scoring: WeightChallenge.Scoring) -> String {
        scoring == .percent ? String(format: "%.1f%%", value) : String(format: "%.1f lb", value)
    }

    static func weighInAlert(friendName: String, scoring: WeightChallenge.Scoring,
                             progress: WeightChallengeEngine.Progress, previousLeader: String?,
                             newest: WeightChallenge.FriendWeighIn,
                             prior: WeightChallenge.FriendWeighIn?) -> Alert {
        var parts: [String] = []
        if let prior {
            let change = newest.pounds - prior.pounds
            if abs(change) < 0.05 {
                parts.append("\(friendName) held steady since their last weigh-in.")
            } else {
                parts.append("\(friendName) \(change < 0 ? "−" : "+")\(String(format: "%.1f", abs(change))) lb since their last weigh-in.")
            }
        } else {
            parts.append("\(friendName) posted their first weigh-in.")
        }
        let by = margin(progress.margin, scoring: scoring)
        let was = previousLeader
        switch progress.leader {
        case .friend:
            parts.append(was == "friend" ? "\(friendName) leads by \(by)." : "\(friendName) took the lead by \(by). Time to answer.")
        case .you:
            parts.append(was == "you" || was == nil ? "You're still ahead by \(by)." : "You're back in front by \(by).")
        case .tied:
            parts.append("It's dead even.")
        case .unknown:
            break
        }
        return Alert(title: "\(friendName) just weighed in", body: parts.joined(separator: " "))
    }

    // MARK: - Nudges

    /// Why a nudge is earned now, if it is.
    static func nudgeReason(before: Snapshot?, after: Snapshot,
                            newest: WeightChallenge.FriendWeighIn?, prior: WeightChallenge.FriendWeighIn?) -> NudgeReason? {
        guard let before else { return nil }
        if before.leader != after.leader {
            if after.leader == "you" { return .tookLead }
            if after.leader == "friend" { return .lostLead }
        }
        if let newest, let prior, prior.pounds - newest.pounds >= 1.5 { return .friendBigDrop }
        if after.yourStreak != before.yourStreak, [7, 14, 21, 28].contains(after.yourStreak) {
            return .streak(after.yourStreak)
        }
        return nil
    }

    /// When a nudge may go out: now, or 8:05 the next morning if it's
    /// quiet hours (9 PM – 8 AM). nil when two already went out this week
    /// or the last was under 36 hours ago.
    static func nudgeTime(now: Date, sent: [Date], calendar: Calendar = .current) -> Date? {
        let week = now.addingTimeInterval(-7 * 86_400)
        let recent = sent.filter { $0 > week }
        guard recent.count < 2 else { return nil }
        if let last = recent.max(), now.timeIntervalSince(last) < 36 * 3600 { return nil }
        let hour = calendar.component(.hour, from: now)
        if hour >= 8 && hour < 21 { return now }
        let morning = hour >= 21 ? calendar.date(byAdding: .day, value: 1, to: now) ?? now : now
        return calendar.date(bySettingHour: 8, minute: 5, second: 0, of: morning)
    }

    /// When Apple Intelligence can't write one.
    static func cannedLine(_ reason: NudgeReason, friendName: String) -> String {
        switch reason {
        case .tookLead:      return "Top of the board. Tell \(friendName) to enjoy the view from second. 👑"
        case .lostLead:      return "\(friendName) just passed you. Tonight's dinner decides how long that lasts."
        case .friendBigDrop: return "\(friendName) dropped a big one. Respect it — then out-walk it today."
        case .streak(let n): return "\(n) mornings on the scale in a row. \(friendName) can't say that."
        }
    }

    static func nudgeTitle(_ reason: NudgeReason, friendName: String) -> String {
        switch reason {
        case .tookLead:      return "You took the lead 🔥"
        case .lostLead:      return "\(friendName) is ahead"
        case .friendBigDrop: return "\(friendName) means business"
        case .streak(let n): return "\(n)-day weigh-in streak"
        }
    }
}
