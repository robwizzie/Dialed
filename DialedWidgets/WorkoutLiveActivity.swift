//
//  WorkoutLiveActivity.swift
//  DialedWidgets
//
//  The workout on your Lock Screen and in the Dynamic Island: the
//  exercise, the next set to lift, sets done, and a rest countdown that
//  ticks on its own (no updates needed while you rest).
//

import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(title: context.attributes.title, startedAt: context.attributes.startedAt,
                                  state: context.state)
                .activityBackgroundTint(Theme.paper)
                .activitySystemActionForegroundColor(Theme.ink)
                .widgetURL(URL(string: "dialed://home"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(state.setsDone)/\(state.setsTotal)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "dumbbell.fill")
                            .foregroundColor(Theme.green)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestOrElapsed(state: state, startedAt: context.attributes.startedAt)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: 70, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.exercise ?? "All sets done")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !state.isFinished {
                        HStack {
                            Text("Set \(state.setNumber) of \(state.setCount)")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Next: \(state.nextText)")
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(Theme.green)
            } compactTrailing: {
                if let rest = state.restRange {
                    Text(timerInterval: rest, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                        .foregroundColor(Theme.orange)
                } else {
                    Text(state.isFinished ? "Done" : state.nextText)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 70)
                }
            } minimal: {
                if let rest = state.restRange {
                    Text(timerInterval: rest, countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.orange)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundColor(Theme.green)
                }
            }
            .widgetURL(URL(string: "dialed://home"))
            .keylineTint(Theme.green)
        }
    }
}

/// Lock Screen banner.
private struct WorkoutLockScreenView: View {
    let title: String
    let startedAt: Date
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(title.uppercased(), systemImage: "dumbbell.fill")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Theme.inkTertiary)
                Spacer()
                Text(startedAt, style: .timer)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Theme.inkTertiary)
                    .frame(maxWidth: 60, alignment: .trailing)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.exercise ?? "All sets done 💪")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    if !state.isFinished {
                        Text("Set \(state.setNumber) of \(state.setCount) · next \(state.nextText)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let rest = state.restRange {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("REST")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(Theme.orangeText)
                        Text(timerInterval: rest, countsDown: true)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(Theme.orangeText)
                            .frame(maxWidth: 80, alignment: .trailing)
                    }
                }
            }
            ProgressView(value: Double(state.setsDone), total: Double(max(1, state.setsTotal)))
                .tint(Theme.green)
            Text("\(state.setsDone) of \(state.setsTotal) sets")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.inkTertiary)
        }
        .padding(16)
    }
}

/// Rest countdown while resting, otherwise time since you started.
private struct RestOrElapsed: View {
    let state: WorkoutActivityAttributes.ContentState
    let startedAt: Date

    var body: some View {
        if let rest = state.restRange {
            Text(timerInterval: rest, countsDown: true)
                .monospacedDigit()
                .foregroundColor(Theme.orange)
        } else {
            Text(startedAt, style: .timer)
                .monospacedDigit()
        }
    }
}
