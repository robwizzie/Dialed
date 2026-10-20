//
//  ChallengeWidget.swift
//  DialedWidgets
//
//  The weight-loss challenge scoreboard — you vs your friend, who's
//  leading and by how much, days left, the pace you need to finish ahead,
//  progress to your goal and your weigh-in streak — plus the countdown to
//  your goal day. Turns orange-hot for the final push (last 14 days).
//  Home Screen (small, medium) and Lock Screen (rectangular, circular,
//  inline).
//

import SwiftUI
import WidgetKit

struct DialedChallengeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DialedChallengeWidget", provider: DialedProvider()) { entry in
            ChallengeWidgetView(entry: entry)
        }
        .configurationDisplayName("Race")
        .description("You vs your friend: who leads, by how much, the pace to win, and days left.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
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
            case .accessoryCircular:
                circular
                    .containerBackground(for: .widget) { Color.clear }
            case .accessoryInline:
                inline
                    .containerBackground(for: .widget) { Color.clear }
            case .systemMedium:
                medium.dialedBackground(challenge?.isFinalPush == true ? .peach : .lavender)
            default:
                small.dialedBackground(challenge?.isFinalPush == true ? .peach : .lavender)
            }
        }
        .widgetURL(WidgetLink.challenge.url)
    }

    // MARK: Sizes

    @ViewBuilder
    private var small: some View {
        if let c = challenge {
            VStack(alignment: .leading, spacing: 0) {
                WidgetTitle(icon: c.isFinalPush ? "flame.fill" : "trophy.fill",
                            title: c.isFinalPush ? "Final push" : "Day \(c.dayNumber)",
                            tint: c.isFinalPush ? Theme.orange : Theme.amber,
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
                    WidgetTitle(icon: c.isFinalPush ? "flame.fill" : "trophy.fill",
                                title: c.isFinalPush ? "Final push" : "Race", tint: c.isFinalPush ? Theme.orange : Theme.amber)
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
                    if let pace = paceLine(c) {
                        Spacer(minLength: 6)
                        Text(pace)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(paceTint(c))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 8) {
                    ZStack {
                        ProgressRing(progress: c.timeProgress, tint: c.isFinalPush ? Theme.orange : Theme.lavender, lineWidth: 7)
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
                Text(paceLine(c) ?? (c.isFinalPush ? "Final push · \(c.daysLeft)d left" : "Day \(c.dayNumber) of \(c.totalDays)"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    /// Lock Screen ring: days left around the edge, your lead (or deficit) inside.
    @ViewBuilder
    private var circular: some View {
        if let c = challenge {
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: c.timeProgress) {
                    Image(systemName: c.isFinalPush ? "flame.fill" : "trophy.fill")
                } currentValueLabel: {
                    VStack(spacing: -2) {
                        Text(signedLead(c))
                            .font(.system(size: 13, weight: .bold))
                            .minimumScaleFactor(0.6)
                        Text("\(c.daysLeft)d")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "trophy")
            }
        }
    }

    /// One line above the clock: "👑 +1.2 lb on Dave · 12d".
    @ViewBuilder
    private var inline: some View {
        if let c = challenge {
            switch c.leader {
            case "you":    Text("👑 \(signedLead(c)) on \(c.friendName) · \(c.daysLeft)d")
            case "friend": Text("\(c.friendName) \(amount(c.margin, c)) up · \(c.daysLeft)d left")
            case "tied":   Text("Tied with \(c.friendName) · \(c.daysLeft)d")
            default:       Text("\(c.daysLeft) days vs \(c.friendName)")
            }
        } else {
            Text("Start a challenge")
        }
    }

    // MARK: Pieces

    /// "+1.2 lb" when you lead, "−0.4 lb" when behind, "0" tied.
    private func signedLead(_ c: WidgetInsights.Challenge) -> String {
        let unit = c.scoresPercent ? "%" : ""
        switch c.leader {
        case "you":    return "+" + String(format: "%.1f", c.margin) + unit
        case "friend": return "−" + String(format: "%.1f", c.margin) + unit
        default:       return "0"
        }
    }

    /// "Need 1.4 lb/wk · you're on 1.7"
    private func paceLine(_ c: WidgetInsights.Challenge) -> String? {
        guard let needed = c.neededPace, c.raceStatus != nil, c.raceStatus != "unknown" else { return nil }
        if needed <= 0.05 { return "Far enough ahead to hold steady" }
        let you = c.yourPace.map { " · you're on \(String(format: "%.1f", $0))" } ?? ""
        return "Need \(String(format: "%.1f", needed)) lb/wk\(you)"
    }

    private func paceTint(_ c: WidgetInsights.Challenge) -> Color {
        c.raceStatus == "behind" ? Theme.orangeText : Theme.greenText
    }

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
