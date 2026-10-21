//
//  MorningCard.swift
//  Dialed
//
//  Good morning: the top of Home from 4 AM to noon. Last night's sleep
//  paints the sky (a radiant sunrise for a great night, down to a grey
//  drizzle for a rough one) with the score, hours, bed → wake and stage
//  mix on a frosted panel over it. Below, the three most useful reads for
//  the day (the rest one tap away) and one line worth knowing. Dismiss it
//  and it stays tucked away until tomorrow.
//

import SwiftUI

struct HomeMorningCard: View {
    let firstName: String
    let night: HealthInsights.Night?
    /// Recent nights (oldest first), for "vs your week".
    let recentNights: [HealthInsights.Night]
    let readiness: Int?
    let weightReadings: [WeightReading]
    let mileStreak: Int
    let progress: WeightChallengeEngine.Progress?
    let friendName: String?
    let goalEvent: GoalEvent?
    var onWeighIn: () -> Void = {}
    var onOpenSleep: () -> Void = {}
    var onDismiss: () -> Void

    @State private var shownScore: Double = 0
    @State private var showAllChips = false
    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    private var score: Int? { night.map(HealthInsights.sleepScore) }
    private var tier: SleepVisuals.MorningTier { SleepVisuals.MorningTier(score: score ?? 72) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hero
            chips
            if let line = funLine {
                HStack(spacing: 8) {
                    Image(systemName: line.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(line.tint)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(line.tint.opacity(0.15)))
                    Text(line.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.track.opacity(0.7)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .fill(Neka.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .stroke(Neka.hairline, lineWidth: 0.5)
        )
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.2)) {
                shownScore = Double(score ?? 0) / 100
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundColor(Neka.inkTertiary)
                Text(firstName.isEmpty ? "Good morning" : "Good morning, \(firstName)")
                    .font(Neka.display(22, weight: .bold))
                    .foregroundColor(Neka.ink)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Neka.inkSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Neka.track))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide until tomorrow")
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Hero: the sky last night earned

    private var hero: some View {
        Button(action: onOpenSleep) {
            ZStack(alignment: .bottom) {
                MorningSky(score: score)
                    .frame(height: 236)
                Group {
                    if let night, let score {
                        sleepPanel(night, score: score)
                    } else {
                        noSleep
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topLeading) {
                Label(tierTitle, systemImage: tier.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.22)))
                    .padding(12)
            }
        }
        .buttonStyle(.dialedScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(score.map { "Sleep score \($0), \(HealthInsights.label(for: $0)). \(tier.verdict)" } ?? "No sleep recorded")
    }

    private var tierTitle: String {
        switch tier {
        case .radiant: return "Sunrise"
        case .mellow:  return "Easy dawn"
        case .hazy:    return "Hazy morning"
        case .drizzly: return "Grey start"
        }
    }

    private func sleepPanel(_ night: HealthInsights.Night, score: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(Neka.ink.opacity(0.08), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: shownScore)
                    .stroke(AngularGradient(colors: MorningSky.ringColors(tier), center: .center),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -3) {
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Neka.ink)
                        .contentTransition(.numericText())
                    Text(HealthInsights.label(for: score).uppercased())
                        .font(.system(size: 8.5, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                Text(tier.verdict)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(duration(night.asleepMinutes))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Neka.ink)
                    Text("\(night.bedtime.formatted(date: .omitted, time: .shortened)) – \(night.wakeTime.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                stageBar(night)
                if let delta = weekDelta(score) {
                    Text(delta >= 0 ? "▲ \(delta) vs your week" : "▼ \(-delta) vs your week")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(delta >= 0 ? Neka.greenText : Neka.orangeText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Deep / REM / light / awake as one bar.
    @ViewBuilder
    private func stageBar(_ n: HealthInsights.Night) -> some View {
        let parts: [(Int, Color, String)] = [
            (n.deepMinutes ?? 0, Neka.lavender, "Deep"),
            (n.remMinutes ?? 0, Neka.sky, "REM"),
            (n.lightMinutes ?? 0, Neka.blue.opacity(0.45), "Light"),
            (n.awakeMinutes ?? 0, Neka.orange.opacity(0.7), "Awake")
        ]
        let total = max(1, parts.reduce(0) { $0 + $1.0 })
        if parts.reduce(0, { $0 + $1.0 }) > 0 {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                            if p.0 > 0 {
                                Capsule().fill(p.1)
                                    .frame(width: max(4, (geo.size.width - 6) * CGFloat(p.0) / CGFloat(total)))
                            }
                        }
                    }
                }
                .frame(height: 6)
                HStack(spacing: 8) {
                    ForEach(Array(parts.prefix(2).enumerated()), id: \.offset) { _, p in
                        HStack(spacing: 3) {
                            Circle().fill(p.1).frame(width: 5, height: 5)
                            Text("\(p.2) \(duration(p.0))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Neka.inkSecondary)
                        }
                    }
                }
            }
        }
    }

    private var noSleep: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Neka.lavenderText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Neka.lavenderSoft))
            Text("No sleep from last night yet. Wear your watch to bed and tomorrow's sky shows how you slept.")
                .font(.system(size: 13))
                .foregroundColor(Neka.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Tiles

    private struct Tile: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let value: String
        var action: (() -> Void)? = nil
    }

    private var tileList: [Tile] {
        var out: [Tile] = []
        if let readiness {
            out.append(Tile(id: "ready", icon: "bolt.heart.fill", tint: Neka.green, title: "Readiness",
                            value: "\(readiness) · \(readiness >= 75 ? "Push today" : readiness >= 55 ? "Steady day" : "Go easy")"))
        }
        if let w = weighIn {
            out.append(Tile(id: "weight", icon: "scalemass.fill", tint: Neka.sky, title: "Overnight", value: w))
        } else {
            out.append(Tile(id: "weight", icon: "scalemass.fill", tint: Neka.sky, title: "Weigh-in",
                            value: "Step on the scale", action: onWeighIn))
        }
        let yesterday = MileHistory.load()?.last(2, today: Date()).first?.miles
        out.append(Tile(id: "mile", icon: "figure.walk", tint: Neka.lavender, title: "Mile streak",
                        value: mileStreak > 0
                            ? "🔥 \(mileStreak) day\(mileStreak == 1 ? "" : "s")"
                            : (yesterday.map { String(format: "%.1f mi yesterday", $0) } ?? "Start one today")))
        let session = WorkoutPlanStore.session(on: Date())
        out.append(Tile(id: "workout", icon: session.symbol, tint: Neka.orange, title: "Today",
                        value: session.minutes > 0 ? "\(session.title.components(separatedBy: " · ").first ?? session.title) · \(session.minutes) min" : session.title))
        if let progress, let friendName {
            let lead: String
            switch progress.leader {
            case .you:    lead = "Up on \(friendName)"
            case .friend: lead = "\(friendName) leads"
            default:      lead = "Neck and neck"
            }
            out.append(Tile(id: "challenge", icon: "flag.2.crossed.fill", tint: Neka.rose, title: "Challenge",
                            value: "\(lead) · \(progress.daysLeft)d left"))
        }
        if let goalEvent, let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                                              to: calendar.startOfDay(for: goalEvent.date)).day, days > 0 {
            out.append(Tile(id: "goal", icon: "sparkles", tint: Neka.amber, title: goalEvent.name,
                            value: "\(days) day\(days == 1 ? "" : "s") to go"))
        }
        return out
    }

    /// The first three as a tidy row; the rest one tap away.
    private var chips: some View {
        let list = tileList
        let shown = showAllChips ? list : Array(list.prefix(3))
        return VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(shown) { tile in
                    Group {
                        if let action = tile.action {
                            Button(action: action) { tileBody(tile) }.buttonStyle(.dialedScale)
                        } else {
                            tileBody(tile)
                        }
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            if list.count > 3 {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showAllChips.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showAllChips ? "Less" : "\(list.count - 3) more for today")
                        Image(systemName: showAllChips ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tileBody(_ tile: Tile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: tile.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tile.tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tile.tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.title.uppercased())
                    .font(.system(size: 8.5, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(Neka.inkTertiary)
                    .lineLimit(1)
                Text(tile.value)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.track.opacity(0.7)))
    }

    // MARK: - Helpers

    /// "−0.6 lb 🎉" when you've weighed in today and yesterday-ish.
    private var weighIn: String? {
        let today = calendar.startOfDay(for: Date())
        let sorted = weightReadings.sorted { $0.date < $1.date }
        guard let latest = sorted.last, latest.date >= today else { return nil }
        guard let before = sorted.last(where: { $0.date < today }) else {
            return String(format: "%.1f lb", latest.pounds)
        }
        let change = latest.pounds - before.pounds
        if abs(change) < 0.05 { return String(format: "%.1f lb · same", latest.pounds) }
        return String(format: "%@%.1f lb%@", change < 0 ? "−" : "+", abs(change), change < 0 ? " 🎉" : "")
    }

    private func weekDelta(_ score: Int) -> Int? {
        let others = recentNights.dropLast().suffix(7).map(HealthInsights.sleepScore)
        guard others.count >= 3 else { return nil }
        return score - others.reduce(0, +) / others.count
    }

    /// One upbeat line, from whatever's most notable this morning.
    private var funLine: (icon: String, tint: Color, text: String)? {
        // Up on time? Compared with this morning's scheduled wake-up.
        if let night, calendar.isDateInToday(night.wakeDay) || calendar.isDateInToday(night.wakeTime),
           let planned = WakeSchedule.load().wake(on: night.wakeTime) {
            let late = Int(night.wakeTime.timeIntervalSince(planned) / 60)
            let plan = WakeSchedule.clock(WakeScheduleView.minutes(of: planned))
            if abs(late) <= 10 { return ("alarm.fill", Neka.greenText, "Up right on time for your \(plan) alarm. Consistency is the cheat code.") }
            if late > 30 { return ("alarm", Neka.orangeText, "Up \(late) min after your \(plan) alarm. Lights out a little earlier tonight.") }
        }
        if let score {
            let week = recentNights.suffix(7).map(HealthInsights.sleepScore)
            if week.count >= 4, score >= (week.max() ?? 0) { return ("trophy.fill", Neka.amber, "Best night of your week. Today's a good day to push.") }
            if score < 55 { return ("drop.fill", Neka.sky, "Rough night. Extra water, a walk in daylight, and an early bedtime.") }
            if let night, night.hours >= 8 { return ("battery.100.bolt", Neka.greenText, "8+ hours. Fully charged.") }
        }
        if mileStreak >= 7 { return ("figure.walk", Neka.lavenderText, "A full week of miles in a row. Don't break the chain.") }
        if let progress, progress.leader == .you, let friendName { return ("crown.fill", Neka.amber, "You're ahead of \(friendName). Stay boring, stay winning.") }
        return nil
    }

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
