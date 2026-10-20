//
//  WorkoutLiveActivityController.swift
//  Dialed
//
//  Starts, updates and ends the workout Live Activity for the logger, so
//  the exercise, next set and rest timer sit on the Lock Screen and in the
//  Dynamic Island between sets. One at a time; quietly does nothing when
//  Live Activities are off.
//

import Foundation
import ActivityKit

@MainActor
enum WorkoutLiveActivityController {
    private static var current: Activity<WorkoutActivityAttributes>?

    static var isRunning: Bool { current != nil }

    /// Start (or keep) the activity for a session.
    static func start(title: String, state: WorkoutActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if current == nil {
            // Pick up one left running by an earlier launch instead of stacking a second.
            current = Activity<WorkoutActivityAttributes>.activities.first
        }
        if current != nil {
            update(state)
            return
        }
        do {
            current = try Activity.request(
                attributes: WorkoutActivityAttributes(title: title, startedAt: Date()),
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(3 * 3600)),
                pushType: nil)
        } catch {
            print("⚠️ [LiveActivity] start failed: \(error.localizedDescription)")
        }
    }

    static func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity = current else { return }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(3 * 3600)))
        }
    }

    /// End it; it lingers on the Lock Screen for a few minutes with the final tally.
    static func end(_ state: WorkoutActivityAttributes.ContentState? = nil) {
        let activities = current.map { [$0] } ?? Activity<WorkoutActivityAttributes>.activities
        current = nil
        for activity in activities {
            Task {
                let final = state.map { ActivityContent(state: $0, staleDate: nil) }
                await activity.end(final, dismissalPolicy: .after(Date().addingTimeInterval(5 * 60)))
            }
        }
    }
}
