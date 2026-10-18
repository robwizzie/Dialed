//
//  CoachEngine.swift
//  Dialed
//
//  Turns today's numbers into a short, ranked list of nudges for the Home
//  screen's "Coach" card. Rules-based and pure, so it's testable and it
//  never says anything the data doesn't back up. Tuned for the weight-loss
//  challenge: pace, weigh-ins, water, steps, protein and sleep.
//

import Foundation

struct CoachInsight: Identifiable, Equatable {
    enum Tone: Equatable {
        case win       // green — good news
        case nudge     // orange — do this next
        case info      // blue — context
        case rest      // lavender — sleep / recovery
    }

    let id: String
    let icon: String
    let tone: Tone
    let title: String
    let detail: String
    /// Higher shows first.
    let priority: Int
}

enum CoachEngine {

    struct Inputs {
        var now: Date = Date()
        var progress: WeightChallengeEngine.Progress?
        var friendName: String = "Your friend"
        var scoring: WeightChallenge.Scoring = .percent

        var waterOz: Double = 0
        var waterTargetOz: Double = 120

        var steps: Int = 0
        var stepGoal: Int = 10_000

        var proteinGrams: Double = 0
        var proteinTarget: Double = 190

        var lastSleepHours: Double?
        var hrvToday: Double?
        var hrvBaseline: Double?
    }

    static func insights(_ i: Inputs, calendar: Calendar = .current, limit: Int = 4) -> [CoachInsight] {
        var out: [CoachInsight] = []
        let hour = Double(calendar.component(.hour, from: i.now))
            + Double(calendar.component(.minute, from: i.now)) / 60

        // 1. Weigh-in
        if let p = i.progress, !p.weighedInToday, hour < 12, p.daysLeft > 0 {
            out.append(CoachInsight(
                id: "weigh-in",
                icon: "scalemass.fill",
                tone: .nudge,
                title: "Step on the scale",
                detail: "Morning weigh-ins keep the trend honest" + (p.weighInStreak > 0 ? " — \(p.weighInStreak)-day streak." : "."),
                priority: 95
            ))
        }

        // 2. Head-to-head
        if let p = i.progress {
            let unit = i.scoring == .percent ? "%" : " lb"
            let margin = format(p.margin, decimals: i.scoring == .percent ? 1 : 1) + unit
            switch p.leader {
            case .you:
                out.append(CoachInsight(
                    id: "h2h", icon: "trophy.fill", tone: .win,
                    title: "You lead \(i.friendName) by \(margin)",
                    detail: p.daysLeft > 0 ? "\(p.daysLeft) days left. Protect the lead." : "Final result — nice work.",
                    priority: 80
                ))
            case .friend:
                out.append(CoachInsight(
                    id: "h2h", icon: "flag.checkered", tone: .nudge,
                    title: "\(i.friendName) leads by \(margin)",
                    detail: p.daysLeft > 0 ? "\(p.daysLeft) days to flip it. Today counts." : "Rematch?",
                    priority: 85
                ))
            case .tied:
                out.append(CoachInsight(
                    id: "h2h", icon: "equal.circle.fill", tone: .info,
                    title: "Dead even with \(i.friendName)",
                    detail: "Whoever wins today's choices wins the week.",
                    priority: 82
                ))
            case .unknown:
                break
            }
        }

        // 3. Pace
        if let p = i.progress, p.startWeight != nil, p.currentWeight != nil, p.daysLeft > 0 {
            if p.paceDelta >= 0.3 {
                out.append(CoachInsight(
                    id: "pace", icon: "chart.line.downtrend.xyaxis", tone: .win,
                    title: "\(format(p.paceDelta)) lb ahead of pace",
                    detail: projectionText(p) ?? "Keep doing exactly this.",
                    priority: 70
                ))
            } else if p.paceDelta <= -0.3 {
                out.append(CoachInsight(
                    id: "pace", icon: "gauge.with.dots.needle.33percent", tone: .nudge,
                    title: "\(format(-p.paceDelta)) lb behind pace",
                    detail: "Aim for a ~\(Int(roundTo(p.requiredDailyDeficit, 50))) cal/day deficit to hit −\(format(p.goalLossLbs, decimals: 0)) lb.",
                    priority: 88
                ))
            } else {
                out.append(CoachInsight(
                    id: "pace", icon: "checkmark.seal.fill", tone: .win,
                    title: "Right on pace",
                    detail: projectionText(p) ?? "Steady wins this.",
                    priority: 60
                ))
            }
        }

        // 4. Water — expect a straight line from 7 AM to 9 PM.
        if i.waterTargetOz > 0 {
            let expectedFraction = max(0, min(1, (hour - 7) / 14))
            let expected = i.waterTargetOz * expectedFraction
            let behind = expected - i.waterOz
            if i.waterOz >= i.waterTargetOz {
                out.append(CoachInsight(
                    id: "water", icon: "drop.fill", tone: .win,
                    title: "Water goal hit",
                    detail: "\(Int(i.waterOz)) oz today. Hydration blunts hunger.",
                    priority: 30
                ))
            } else if behind >= 12 {
                let catchUp = Int(roundTo(behind, 4))
                out.append(CoachInsight(
                    id: "water", icon: "drop.fill", tone: .nudge,
                    title: "Drink \(catchUp) oz to catch up",
                    detail: "\(Int(i.waterOz)) of \(Int(i.waterTargetOz)) oz. A full bottle before your next meal helps.",
                    priority: 75
                ))
            }
        }

        // 5. Steps — same linear expectation, 7 AM → 9 PM.
        if i.stepGoal > 0 {
            let expected = Double(i.stepGoal) * max(0, min(1, (hour - 7) / 14))
            let behind = expected - Double(i.steps)
            if i.steps >= i.stepGoal {
                out.append(CoachInsight(
                    id: "steps", icon: "figure.walk", tone: .win,
                    title: "\(i.steps.formatted()) steps — goal done",
                    detail: "Every extra 2,000 steps is roughly 100 cal.",
                    priority: 35
                ))
            } else if behind >= 1_500 {
                let minutes = max(10, Int(roundTo(behind / 100, 5)))  // ~100 steps/min
                out.append(CoachInsight(
                    id: "steps", icon: "figure.walk", tone: .nudge,
                    title: "Take a \(minutes)-min walk",
                    detail: "You're \(Int(behind).formatted()) steps behind pace for \(i.stepGoal.formatted()).",
                    priority: 65
                ))
            }
        }

        // 6. Protein — evening check.
        if hour >= 15, i.proteinTarget > 0, i.proteinGrams < i.proteinTarget * 0.6 {
            let left = Int(i.proteinTarget - i.proteinGrams)
            out.append(CoachInsight(
                id: "protein", icon: "fork.knife", tone: .nudge,
                title: "\(left) g protein to go",
                detail: "Protein keeps you full and protects muscle while you cut.",
                priority: 55
            ))
        }

        // 7. Sleep
        if let sleep = i.lastSleepHours, sleep > 0 {
            if sleep < 6.5 {
                out.append(CoachInsight(
                    id: "sleep", icon: "moon.zzz.fill", tone: .rest,
                    title: "Short night: \(format(sleep))h",
                    detail: "Low sleep spikes hunger. Front-load protein and skip late snacks.",
                    priority: 72
                ))
            } else if sleep >= 7.5 {
                out.append(CoachInsight(
                    id: "sleep", icon: "moon.stars.fill", tone: .rest,
                    title: "Solid sleep: \(format(sleep))h",
                    detail: "Cravings are easier to manage today.",
                    priority: 25
                ))
            }
        }

        // 8. HRV vs baseline
        if let hrv = i.hrvToday, let base = i.hrvBaseline, base > 0 {
            let delta = (hrv - base) / base
            if delta >= 0.1 {
                out.append(CoachInsight(
                    id: "hrv", icon: "waveform.path.ecg", tone: .win,
                    title: "HRV up \(Int((delta * 100).rounded()))%",
                    detail: "You're recovered. Good day to push a harder session.",
                    priority: 40
                ))
            } else if delta <= -0.15 {
                out.append(CoachInsight(
                    id: "hrv", icon: "waveform.path.ecg", tone: .rest,
                    title: "HRV down \(Int((-delta * 100).rounded()))%",
                    detail: "Go easier today — walk instead of a hard lift.",
                    priority: 58
                ))
            }
        }

        return Array(out.sorted { $0.priority > $1.priority }.prefix(limit))
    }

    // MARK: - Helpers

    private static func projectionText(_ p: WeightChallengeEngine.Progress) -> String? {
        guard let projected = p.projectedLossAtEnd, projected > 0 else { return nil }
        return "Trend lands you at −\(format(projected)) lb by the final day."
    }

    static func format(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }

    private static func roundTo(_ value: Double, _ step: Double) -> Double {
        (value / step).rounded() * step
    }
}
