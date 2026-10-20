//
//  MorningCard.swift
//  Dialed
//
//  Good morning: the top of Home from 4 AM to noon. Last night's sleep
//  score front and centre (ring, hours, bed → wake, the stage mix, and how
//  it compares with your week), then a handful of quick reads for the day
//  ahead — readiness, the overnight weigh-in, your mile streak, today's
//  workout, the challenge and the countdown to the big day. Dismiss it and
//  it stays tucked away until tomorrow.
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
    private let calendar = Calendar.current

    private var score: Int? { night.map(HealthInsights.sleepScore) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let night, let score {
                sleepBlock(night, score: score)
            } else {
                noSleep
            }
            tiles
            if let line = funLine {
                Text(line)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface.opacity(0.7)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Neka.amberSoft, Neka.lavenderSoft, Neka.skySoft],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                Text(firstName.isEmpty ? "Good morning ☀️" : "Good morning, \(firstName) ☀️")
                    .font(Neka.display(24, weight: .bold))
                    .foregroundColor(Neka.ink)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Neka.inkSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Neka.surface.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide until tomorrow")
        }
    }

    // MARK: - Sleep

    private func sleepBlock(_ night: HealthInsights.Night, score: Int) -> some View {
        Button(action: onOpenSleep) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().stroke(Neka.surface.opacity(0.9), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: shownScore)
                        .stroke(AngularGradient(colors: [Neka.lavender, Neka.sky, Neka.green, Neka.lavender], center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(score)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(Neka.ink)
                            .contentTransition(.numericText())
                        Text(HealthInsights.label(for: score))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Neka.lavenderText)
                    }
                }
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Sleep score", systemImage: "moon.zzz.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                    Text(duration(night.asleepMinutes))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("\(night.bedtime.formatted(date: .omitted, time: .shortened)) → \(night.wakeTime.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                    stageBar(night)
                    if let delta = weekDelta(score) {
                        Text(delta >= 0 ? "▲ \(delta) vs your week" : "▼ \(-delta) vs your week")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(delta >= 0 ? Neka.greenText : Neka.orangeText)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep score \(score), \(HealthInsights.label(for: score)), \(duration(night.asleepMinutes)) asleep")
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
                .frame(height: 7)
                HStack(spacing: 8) {
                    ForEach(Array(parts.prefix(2).enumerated()), id: \.offset) { _, p in
                        HStack(spacing: 3) {
                            Circle().fill(p.1).frame(width: 6, height: 6)
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
            Image(systemName: "moon.zzz")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Neka.lavenderText)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Neka.surface.opacity(0.8)))
            Text("No sleep from last night yet — wear your watch to bed and it'll show here with a score.")
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
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

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(tileList) { tile in
                Group {
                    if let action = tile.action {
                        Button(action: action) { tileBody(tile) }.buttonStyle(.dialedScale)
                    } else {
                        tileBody(tile)
                    }
                }
            }
        }
    }

    private func tileBody(_ tile: Tile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tile.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tile.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Neka.surface))
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
                Text(tile.value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.surface.opacity(0.7)))
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
    private var funLine: String? {
        // Up on time? Compared with this morning's scheduled wake-up.
        if let night, calendar.isDateInToday(night.wakeDay) || calendar.isDateInToday(night.wakeTime),
           let planned = WakeSchedule.load().wake(on: night.wakeTime) {
            let late = Int(night.wakeTime.timeIntervalSince(planned) / 60)
            if abs(late) <= 10 { return "⏰ Up right on time (\(WakeSchedule.clock(WakeScheduleView.minutes(of: planned))) plan). Consistency is the cheat code." }
            if late > 30 { return "⏰ Up \(late) min after your \(WakeSchedule.clock(WakeScheduleView.minutes(of: planned))) plan. Try lights out a bit earlier tonight." }
        }
        if let score {
            let week = recentNights.suffix(7).map(HealthInsights.sleepScore)
            if week.count >= 4, score >= (week.max() ?? 0) { return "🏆 Best night of your week. Use it — today's a good day to push." }
            if score < 55 { return "😴 Rough night. Extra water, a walk in daylight, and an early bedtime tonight." }
            if let night, night.hours >= 8 { return "🔋 8+ hours — fully charged." }
        }
        if mileStreak >= 7 { return "🚶 A full week of miles in a row. Don't break the chain." }
        if let progress, progress.leader == .you, let friendName { return "👑 You're ahead of \(friendName). Stay boring, stay winning." }
        return nil
    }

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
