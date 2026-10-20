//
//  AvatarEvolution.swift
//  Dialed
//
//  Your avatar gets fitter as you do. Six stages from how far your trend
//  weight has come toward your goal, plus a "glow" from your streaks. The
//  stage steers the avatar prompt — always about getting stronger, more
//  athletic and more confident, never about body size as a flaw — and it
//  only ever moves up: a heavy week doesn't take a level away. Pure
//  Foundation, tested.
//

import Foundation

enum AvatarEvolution {

    struct Stage: Equatable {
        let level: Int
        let name: String
        let blurb: String
        /// Share of the goal reached to unlock this stage.
        let threshold: Double
        /// Added to the avatar prompt.
        let prompt: String
    }

    static let stages: [Stage] = [
        Stage(level: 1, name: "Starting line", blurb: "Day one energy. Everything from here is progress.", threshold: 0,
              prompt: "relaxed and ready to start"),
        Stage(level: 2, name: "Warming up", blurb: "Habits are forming. You look like someone who trains.", threshold: 0.15,
              prompt: "looking energetic and a little more athletic, upright posture"),
        Stage(level: 3, name: "Building", blurb: "Stronger shoulders, more spring in the step.", threshold: 0.35,
              prompt: "a bit leaner and fitter, stronger shoulders, standing tall"),
        Stage(level: 4, name: "Athletic", blurb: "People are starting to ask what you're doing.", threshold: 0.55,
              prompt: "noticeably leaner and more athletic, confident posture"),
        Stage(level: 5, name: "Sharp", blurb: "Lean, strong and carrying yourself like it.", threshold: 0.75,
              prompt: "lean and athletic with defined arms, confident and sharp"),
        Stage(level: 6, name: "Peak", blurb: "Goal shape. This is the version of you that showed up.", threshold: 0.95,
              prompt: "in peak shape, lean and strong, beaming with confidence")
    ]

    struct Inputs: Equatable {
        /// Where you started and where you're headed, lbs.
        var startWeight: Double
        var goalWeight: Double
        var trendWeight: Double
        /// Longest of your live streaks (mile, weigh-ins, logging), days.
        var streakDays: Int
    }

    struct Reading: Equatable {
        let stage: Stage
        /// Share of the goal reached, 0–1.
        let progress: Double
        /// Progress from this stage to the next, 0–1 (1 at the last stage).
        let toNext: Double
        /// Trend lbs still to lose before the next stage (nil at the top).
        let lbsToNext: Double?
        /// 0–3 from streaks: 3+, 7+, 14+ days.
        let glow: Int

        var next: Stage? { stage.level < stages.count ? stages[stage.level] : nil }
    }

    static func read(_ i: Inputs) -> Reading {
        let goalLoss = i.startWeight - i.goalWeight
        let progress = goalLoss > 0 ? max(0, min(1, (i.startWeight - i.trendWeight) / goalLoss)) : 0
        let stage = stages.last { progress >= $0.threshold } ?? stages[0]
        var toNext = 1.0
        var lbsToNext: Double?
        if stage.level < stages.count {
            let next = stages[stage.level]
            toNext = (progress - stage.threshold) / (next.threshold - stage.threshold)
            lbsToNext = max(0, (next.threshold - progress) * goalLoss)
        }
        return Reading(stage: stage, progress: progress, toNext: max(0, min(1, toNext)),
                       lbsToNext: lbsToNext, glow: glow(streakDays: i.streakDays))
    }

    static func glow(streakDays: Int) -> Int {
        switch streakDays {
        case 14...: return 3
        case 7...:  return 2
        case 3...:  return 1
        default:    return 0
        }
    }

    static func stage(level: Int) -> Stage {
        stages[max(1, min(stages.count, level)) - 1]
    }

    /// The level the avatar should be drawn at: the best you've reached.
    /// Returns the new level and whether that's a level-up worth a moment
    /// (not on the very first reading).
    static func settle(stored: Int?, reached: Int) -> (level: Int, leveledUp: Bool) {
        guard let stored else { return (reached, false) }
        return reached > stored ? (reached, true) : (stored, false)
    }
}
