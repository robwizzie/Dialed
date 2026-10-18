//
//  HealthSnapshot.swift
//  Dialed
//
//  A compact, plain-text picture of today — your challenge standing,
//  weight, water, steps, sleep, recovery and fuel. It's what the on-device
//  Apple Intelligence model sees (nothing leaves the phone), and what the
//  no-AI fallbacks use. Pure Foundation so it's unit-testable.
//

import Foundation

struct HealthSnapshot: Equatable {
    var now: Date = Date()
    var firstName: String = ""

    // Challenge
    var friendName: String?
    var challengeDay: Int?
    var challengeDays: Int?
    var daysLeft: Int?
    var scoring: WeightChallenge.Scoring = .percent
    var lostLbs: Double?
    var lostPercent: Double?
    var friendLostLbs: Double?
    var friendLostPercent: Double?
    var leader: WeightChallengeEngine.Leader = .unknown
    var margin: Double = 0
    var goalLossLbs: Double?
    var paceDelta: Double?
    var projectedLossAtEnd: Double?
    var requiredDailyDeficit: Double?

    // Body
    var weight: Double?
    var weighedInToday: Bool = false
    var sleepHours: Double?
    var hrv: Double?
    var hrvBaseline: Double?
    var restingHR: Double?

    // Day
    var waterOz: Double = 0
    var waterTargetOz: Double = 0
    var steps: Int = 0
    var stepGoal: Int = 10_000
    var proteinGrams: Double = 0
    var proteinTarget: Double = 0
    var caloriesIn: Double = 0
    var calorieTarget: Double = 0
    var nextUp: [String] = []

    var hasChallenge: Bool { friendName != nil && challengeDays != nil }

    /// Bullet list for the model's prompt. Only includes what we know —
    /// missing numbers are omitted so the model can't riff on zeros.
    var promptText: String {
        var lines: [String] = []
        let f = DateFormatter()
        f.dateFormat = "EEEE h:mm a"
        lines.append("- Now: \(f.string(from: now))")
        if !firstName.isEmpty { lines.append("- Name: \(firstName)") }

        if hasChallenge, let friend = friendName, let day = challengeDay, let days = challengeDays {
            lines.append("- Weight-loss challenge vs. \(friend): day \(day) of \(days), \(daysLeft ?? 0) days left, scored by \(scoring == .percent ? "% of body weight" : "total pounds")")
            if let lost = lostLbs, let pct = lostPercent {
                lines.append("- You've lost \(Self.n(lost)) lb (\(Self.n(pct))%)")
            }
            if let fl = friendLostLbs, let fp = friendLostPercent {
                lines.append("- \(friend) has lost \(Self.n(fl)) lb (\(Self.n(fp))%)")
            }
            let unit = scoring == .percent ? "%" : " lb"
            switch leader {
            case .you:     lines.append("- You lead by \(Self.n(margin))\(unit)")
            case .friend:  lines.append("- \(friend) leads by \(Self.n(margin))\(unit)")
            case .tied:    lines.append("- It's tied")
            case .unknown: break
            }
            if let goal = goalLossLbs { lines.append("- Your goal: lose \(Self.n(goal)) lb") }
            if let pace = paceDelta {
                lines.append(pace >= 0 ? "- \(Self.n(pace)) lb ahead of goal pace" : "- \(Self.n(-pace)) lb behind goal pace")
            }
            if let proj = projectedLossAtEnd { lines.append("- Trend projects −\(Self.n(proj)) lb by the end") }
            if let deficit = requiredDailyDeficit, deficit > 0 {
                lines.append("- Needs about \(Int(deficit)) kcal/day deficit from here")
            }
        }

        if let w = weight { lines.append("- Weight: \(Self.n(w)) lb\(weighedInToday ? " (weighed in today)" : " (not weighed in today)")") }
        if waterTargetOz > 0 { lines.append("- Water: \(Int(waterOz)) of \(Int(waterTargetOz)) oz") }
        lines.append("- Steps: \(steps) of \(stepGoal)")
        if proteinTarget > 0 { lines.append("- Protein: \(Int(proteinGrams)) of \(Int(proteinTarget)) g") }
        if calorieTarget > 0 { lines.append("- Calories eaten: \(Int(caloriesIn)) of \(Int(calorieTarget)) budget") }
        if let s = sleepHours { lines.append("- Last night's sleep: \(Self.n(s)) h") }
        if let h = hrv {
            if let b = hrvBaseline { lines.append("- HRV \(Int(h)) ms vs. \(Int(b)) ms baseline") } else { lines.append("- HRV \(Int(h)) ms") }
        }
        if let r = restingHR { lines.append("- Resting heart rate: \(Int(r)) bpm") }
        if !nextUp.isEmpty { lines.append("- Coming up: \(nextUp.joined(separator: "; "))") }
        return lines.joined(separator: "\n")
    }

    static func n(_ v: Double) -> String { String(format: "%.1f", v) }
}

// MARK: - No-AI fallbacks

/// Tone for the trash-talk generator on the Challenge tab.
enum TrashTalkTone: String, CaseIterable, Identifiable {
    case friendly, savage, hype

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friendly: return "Friendly"
        case .savage:   return "Savage"
        case .hype:     return "Hype"
        }
    }

    var emoji: String {
        switch self {
        case .friendly: return "😄"
        case .savage:   return "🔥"
        case .hype:     return "💪"
        }
    }
}

/// Templated text used when Apple Intelligence isn't available (older
/// phone, turned off, or model still downloading). Keeps every feature
/// working everywhere.
enum DialedAIFallback {

    static func trashTalk(_ s: HealthSnapshot, tone: TrashTalkTone, variant: Int = 0) -> String {
        let friend = s.friendName ?? "buddy"
        let unit = s.scoring == .percent ? "%" : " lb"
        let margin = HealthSnapshot.n(s.margin) + unit
        let days = s.daysLeft.map { "\($0) days" } ?? "the rest of the month"

        let options: [String]
        switch (s.leader, tone) {
        case (.you, .friendly):
            options = ["Up \(margin) on you, \(friend). Plenty of time — \(days) — but the scale and I are getting along great 😄",
                       "Friendly update: I'm ahead by \(margin). Drink some water and try to keep up 💧"]
        case (.you, .savage):
            options = ["\(margin) ahead, \(friend). Might want to put the fork down 🍕🚫",
                       "Scale says I'm up \(margin). You still weighing in or did you hide it? 🔥"]
        case (.you, .hype):
            options = ["Up \(margin) with \(days) to go. Let's both finish strong 💪",
                       "Leading by \(margin) — push me, \(friend). Best version of both of us wins 🏁"]
        case (.friend, .friendly):
            options = ["Okay okay, you're up \(margin). Enjoy it while it lasts 😏",
                       "Respect, \(friend) — \(margin) ahead. I'm coming for it though."]
        case (.friend, .savage):
            options = ["Enjoy your \(margin) lead, \(friend). It's a loan, not a gift 🔥",
                       "\(days) left. You're up \(margin). I've had worse odds and better abs."]
        case (.friend, .hype):
            options = ["You're up \(margin) — that just lit a fire. Game on 💪",
                       "Comeback season starts today. \(days) is plenty 🏁"]
        default:
            options = ["Dead even with \(days) left, \(friend). Somebody's gotta blink 👀",
                       "Tied up. Loser buys the celebratory (low-cal) dinner? 🍽️"]
        }
        return options[abs(variant) % options.count]
    }
}
