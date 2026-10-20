//
//  ChallengeWidget.swift
//  DialedWidgets
//
//  The weight-loss challenge scoreboard — you vs your friend, who's
//  leading and by how much, days left, progress to your goal and your
//  weigh-in streak — plus the countdown to your goal day.
//

import SwiftUI
import WidgetKit

struct DialedChallengeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DialedChallengeWidget", provider: DialedProvider()) { entry in
            ChallengeWidgetView(entry: entry)
        }
        .configurationDisplayName("Challenge")
        .description("You vs your friend, days left, and the countdown to your goal day.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct ChallengeWidgetView: View {
    let entry: DialedEntry
    @Environment(\.widgetFamily) private var family

    private var challenge: WidgetInsights.Challenge? { entry.insights?.challenge }
    private var goal: WidgetInsights.Goal? { entry.insights?.goal }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                rectangular
                    .containerBackground(for: .widget) { Color.clear }
            case .systemMedium:
                medium.dialedBackground(.lavender)
            default:
                small.dialedBackground(.lavender)
            }
        }
        .widgetURL(WidgetLink.challenge.url)
    }

    // MARK: Sizes

    @ViewBuilder
    private var small: some View {
        if let c = challenge {
            VStack(alignment: .leading, spacing: 0) {
                WidgetTitle(icon: "trophy.fill", title: "Day \(c.dayNumber)", tint: Theme.amber,
                            trailing: "\(c.daysLeft)d left")
                Spacer(minLength: 4)
                Text(headline(c))
                    .font(Theme.display(16))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                VStack(spacing: 6) {
                    racer("You", c.youLost, c, isYou: true)
                    racer(c.friendName, c.friendLost, c, isYou: false)
                }
                Spacer(minLength: 0)
            }
        } else if let goal {
            goalCountdown(goal)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var medium: some View {
        if let c = challenge {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetTitle(icon: "trophy.fill", title: "Challenge", tint: Theme.amber)
                    Spacer(minLength: 4)
                    Text(headline(c))
                        .font(Theme.display(17))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 8)
                    VStack(spacing: 8) {
                        racer("You", c.youLost, c, isYou: true)
                        racer(c.friendName, c.friendLost, c, isYou: false)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 8) {
                    ZStack {
                        ProgressRing(progress: c.timeProgress, tint: Theme.lavender, lineWidth: 7)
                        VStack(spacing: -2) {
                            Text("\(c.daysLeft)")
                                .font(Theme.display(22))
                                .foregroundStyle(Theme.ink)
                            Text("days left")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 4) {
                        statLine(icon: "target", tint: Theme.greenText,
                                 text: "\(String(format: "%.1f", c.lostLbs)) of \(Fmt.int(c.goalLossLbs)) lb")
                        statLine(icon: "flame.fill", tint: Theme.orangeText,
                                 text: c.weighInStreak > 0 ? "\(c.weighInStreak)-day streak" : "Weigh in today")
                        if let goal {
                            statLine(icon: "calendar", tint: Theme.lavenderText,
                                     text: "\(daysUntil(goal.date))d to \(goal.name)")
                        }
                    }
                }
                .frame(width: 112)
            }
        } else if let goal {
            goalCountdown(goal)
        } else {
            emptyState
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let c = challenge {
                Label(headline(c), systemImage: "trophy.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                    .lineLimit(1)
                Text("You \(amount(c.youLost, c)) · \(c.friendName) \(c.friendLost.map { amount($0, c) } ?? "—")")
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text("Day \(c.dayNumber) of \(c.totalDays)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let goal {
                Label("\(daysUntil(goal.date)) days", systemImage: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .widgetAccentable()
                Text("until \(goal.name)").font(.system(size: 12))
            } else {
                Label("No challenge yet", systemImage: "trophy")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }

    // MARK: Pieces

    private func headline(_ c: WidgetInsights.Challenge) -> String {
        let lead = amount(c.margin, c)
        switch c.leader {
        case "you":    return "You lead by \(lead) 👑"
        case "friend": return "\(c.friendName) leads by \(lead)"
        case "tied":   return "Dead even 🤝"
        default:       return c.weighedInToday ? "Waiting on \(c.friendName)" : "Step on the scale"
        }
    }

    private func amount(_ value: Double, _ c: WidgetInsights.Challenge) -> String {
        c.scoresPercent ? String(format: "%.1f%%", value) : String(format: "%.1f lb", value)
    }

    /// One lane of the race: name, a bar scaled against the leader, the number.
    private func racer(_ name: String, _ lost: Double?, _ c: WidgetInsights.Challenge, isYou: Bool) -> some View {
        let best = max(c.youLost, c.friendLost ?? 0, 0.1)
        let leads = (c.leader == "you") == isYou && c.leader != "tied" && c.leader != "unknown"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if leads {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.amber)
                }
                Spacer(minLength: 4)
                Text(lost.map { amount($0, c) } ?? "—")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            CapsuleBar(progress: max(0, lost ?? 0) / best,
                       tint: isYou ? Theme.green : Theme.lavender, height: 6)
        }
    }

    private func statLine(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func goalCountdown(_ goal: WidgetInsights.Goal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetTitle(icon: "calendar", title: goal.name, tint: Theme.lavender)
            Spacer(minLength: 4)
            ValueText(value: "\(daysUntil(goal.date))", unit: "days", size: 40)
            Text("until \(goal.date.formatted(.dateTime.month(.abbreviated).day()))")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 4)
            if let projected = goal.projectedWeight {
                StatusPill(text: "On track for \(Fmt.int(projected)) lb", icon: "chart.line.downtrend.xyaxis",
                           tint: Theme.lavenderText, fill: Theme.lavenderSoft)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.amber)
            Text("Start a challenge")
                .font(Theme.display(14))
                .foregroundStyle(Theme.ink)
            Text("Race a friend in Dialed")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date),
                                              to: calendar.startOfDay(for: date)).day ?? 0)
    }
}

#Preview("Small", as: .systemSmall) { DialedChallengeWidget() } timeline: { DialedEntry.preview }
#Preview("Medium", as: .systemMedium) { DialedChallengeWidget() } timeline: { DialedEntry.preview }
