//
//  MorningCard.swift
//  Dialed
//
//  Good morning: the top of Home from 4 AM to noon. The whole card is the
//  sky last night's sleep earned (a radiant sunrise for a great night,
//  down to a grey drizzle for a rough one), with the sun riding an arc as
//  high as the score. Over it: the greeting, the score and its verdict,
//  the night in one frosted row, a line worth knowing, and a swipeable
//  row of chips for the day. Dismiss it and it stays tucked away until
//  tomorrow.
//

import SwiftUI

struct HomeMorningCard: View {
    let firstName: String
    let night: HealthInsights.Night?
    /// Recent nights (oldest first), for how last night compares.
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
    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    private var score: Int? { night.map(HealthInsights.sleepScore) }
    private var tier: SleepVisuals.MorningTier { SleepVisuals.MorningTier(score: score ?? 72) }

    /// Text sits right on the sky: deep ink on a daytime sky, white at night.
    private var ink: Color { scheme == .dark ? .white : Color(hex: "16202E") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // Open sky for the sun to climb.
            Color.clear.frame(height: 84)
            hero
            chips
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { MorningSky(score: score, sunOnArc: score != nil) }
        .clipShape(RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .stroke(.white.opacity(scheme == .dark ? 0.08 : 0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 18, y: 8)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.2)) {
                shownScore = Double(score ?? 0)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.3)
                    .foregroundColor(ink.opacity(0.7))
                Text(firstName.isEmpty ? "Good morning" : "Good morning,\n\(firstName)")
                    .font(Neka.display(26, weight: .bold))
                    .foregroundColor(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ink.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide until tomorrow")
        }
    }

    // MARK: - Hero: score, verdict, the night in one row

    private var hero: some View {
        Button(action: onOpenSleep) {
            VStack(alignment: .leading, spacing: 10) {
                if let night, let score {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(Int(shownScore.rounded()))")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundColor(ink)
                                .contentTransition(.numericText(value: shownScore))
                                .monospacedDigit()
                            VStack(alignment: .leading, spacing: 0) {
                                Text(HealthInsights.label(for: score).uppercased())
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(0.8)
                                    .foregroundColor(ink)
                                Text("sleep score")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(ink.opacity(0.7))
                            }
                        }
                        Text(tier.verdict(weekDelta: weekDelta(score)))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    sleepRow(night)
                } else {
                    noSleep
                }
                if let line = funLine {
                    Label(line.text, systemImage: line.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ink)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(2)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.dialedScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(score.map { "Sleep score \($0), \(HealthInsights.label(for: $0)). \(tier.verdict)" } ?? "No sleep recorded")
        .accessibilityHint("Opens sleep details")
    }

    /// Hours, bed → wake and the stage mix on one frosted row.
    private func sleepRow(_ night: HealthInsights.Night) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.lavenderText)
                Text(duration(night.asleepMinutes))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Neka.ink)
                Text("\(night.bedtime.formatted(date: .omitted, time: .shortened)) – \(night.wakeTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            stageBar(night)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Deep / REM / light / awake as one slim bar.
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
            HStack(spacing: 10) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                            if p.0 > 0 {
                                Capsule().fill(p.1)
                                    .frame(width: max(3, (geo.size.width - 6) * CGFloat(p.0) / CGFloat(total)))
                            }
                        }
                    }
                }
                .frame(height: 4)
                ForEach(Array(parts.prefix(2).enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 3) {
                        Circle().fill(p.1).frame(width: 5, height: 5)
                        Text("\(p.2) \(duration(p.0))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                            .fixedSize()
                    }
                }
            }
        }
    }

    private var noSleep: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Neka.lavenderText)
            Text("No sleep from last night yet. Wear your watch to bed and tomorrow's sky shows how you slept.")
                .font(.system(size: 13))
                .foregroundColor(Neka.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Chips

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

    /// Everything worth a glance today, as one row of frosted chips.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tileList) { tile in
                    if let action = tile.action {
                        Button(action: action) { chip(tile) }.buttonStyle(.dialedScale)
                    } else {
                        chip(tile)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ tile: Tile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tile.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tile.tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tile.tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(tile.title.uppercased())
                    .font(.system(size: 8.5, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(Neka.inkTertiary)
                    .lineLimit(1)
                Text(tile.value)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
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
