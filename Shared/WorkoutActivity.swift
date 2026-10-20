//
//  WorkoutActivity.swift
//  Dialed (app + DialedWidgets)
//
//  The Live Activity shown on the Lock Screen and in the Dynamic Island
//  while you log a workout: what you're on, the next set's weight × reps,
//  sets done, and the rest countdown. The app starts and updates it
//  (WorkoutLiveActivityController); the widget extension draws it.
//
//  Compiled into both targets.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "Bench press", or nil once every set is done.
        var exercise: String?
        /// 1-based set number within the exercise, and how many it has.
        var setNumber: Int
        var setCount: Int
        /// The next set: weight (nil = bodyweight) × reps.
        var nextWeight: Double?
        var nextReps: Int
        /// Rest countdown, when one is running.
        var restEndsAt: Date?
        var setsDone: Int
        var setsTotal: Int

        var isFinished: Bool { exercise == nil }

        /// now…rest end while resting (never an invalid range).
        var restRange: ClosedRange<Date>? {
            let now = Date()
            guard let end = restEndsAt, end > now else { return nil }
            return now...end
        }

        /// "185 lb × 8" / "× 15"
        var nextText: String {
            let reps = "× \(nextReps)"
            guard let w = nextWeight, w > 0 else { return reps }
            let lb = w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
            return "\(lb) lb \(reps)"
        }
    }

    /// "Strength A"
    var title: String
    var startedAt: Date
}
#endif
