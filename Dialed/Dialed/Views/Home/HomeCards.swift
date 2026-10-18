//
//  HomeCards.swift
//  Dialed
//
//  The cards that stack under the Home hero: the challenge scoreboard,
//  body-state strip, metric tiles, fuel, today's timeline and the coach.
//

import SwiftUI

// MARK: - Metric tile shell

struct HomeMetricTile<Visual: View>: View {
    let title: String
    let value: String
    var unit: String? = nil
    var wash: Neka.Wash = .plain
    var showsArrow: Bool = false
    var pill: (text: String, tint: Color, fill: Color)? = nil
    var footer: String? = nil
    var footerTrailing: String? = nil
    @ViewBuilder var visual: () -> Visual

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NekaTileHeader(title: title, showsArrow: showsArrow)
            NekaValue(value: value, unit: unit, size: 34)
            if let pill {
                NekaPill(text: pill.text, tint: pill.tint, fill: pill.fill)
            }
            Spacer(minLength: 4)
            visual()
                .frame(maxWidth: .infinity)
            if footer != nil || footerTrailing != nil {
                HStack {
                    if let footer {
                        Text(footer)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer(minLength: 2)
                    if let footerTrailing {
                        Text(footerTrailing)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 184, maxHeight: 184, alignment: .topLeading)
        .nekaCard(cornerRadius: Neka.tileRadius, wash: wash)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Challenge scoreboard

struct HomeChallengeCard: View {
    let challenge: WeightChallenge?
    let progress: WeightChallengeEngine.Progress?
    var onSetUp: () -> Void

    var body: some View {
        if let challenge, let progress {
            activeCard(challenge, progress)
        } else {
            setupCard
        }
    }

    private var setupCard: some View {
        Button(action: onSetUp) {
            HStack(spacing: 14) {
                NekaIconBadge(systemName: "flag.2.crossed.fill", tint: Neka.orange, fill: Color.white.opacity(0.8), size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start your weight-loss challenge")
                        .font(Neka.title)
                        .foregroundColor(Neka.ink)
                    Text("Add your friend, the dates and your goal. Dialed keeps score.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(16)
            .nekaCard(wash: .peach)
        }
        .buttonStyle(.dialedScale)
    }

    private func activeCard(_ c: WeightChallenge, _ p: WeightChallengeEngine.Progress) -> some View {
        let isPercent = c.scoring == .percent
        let yourScore = isPercent ? p.lostPercent : p.lostLbs
        let theirScore = isPercent ? p.friend?.lostPercent : p.friend?.lostLbs
        let scale = max(abs(yourScore), abs(theirScore ?? 0), isPercent ? 1 : 2)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Challenge vs. \(c.friendDisplayName)")
                    .font(Neka.label)
                    .foregroundColor(Neka.ink)
                Spacer()
                NekaPill(
                    text: p.daysLeft > 0 ? "Day \(p.dayNumber) of \(p.totalDays)" : "Final",
                    tint: Neka.ink, fill: Color.white.opacity(0.85)
                )
            }

            HStack(alignment: .firstTextBaseline) {
                NekaValue(value: signed(-p.lostLbs), unit: "lb", size: 44)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f%%", p.lostPercent))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("of body weight")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
            }

            VStack(spacing: 8) {
                scoreRow(name: "You", value: yourScore, scale: scale, isPercent: isPercent, tint: Neka.green)
                scoreRow(name: c.friendDisplayName, value: theirScore, scale: scale, isPercent: isPercent, tint: Neka.orange)
            }

            HStack(spacing: 6) {
                Image(systemName: leaderIcon(p.leader))
                    .font(.system(size: 12, weight: .semibold))
                Text(leaderText(c, p))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if p.daysLeft > 0 {
                    Text("\(p.daysLeft) days left")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .nekaCard(wash: p.leader == .friend ? .peach : .mint)
    }

    private func scoreRow(name: String, value: Double?, scale: Double, isPercent: Bool, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.ink)
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)
            NekaProgressBar(progress: max(0, (value ?? 0) / scale), tint: tint, height: 8)
            Text(value.map { isPercent ? String(format: "%.1f%%", $0) : String(format: "%.1f lb", $0) } ?? "—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.ink)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func leaderIcon(_ leader: WeightChallengeEngine.Leader) -> String {
        switch leader {
        case .you:     return "trophy.fill"
        case .friend:  return "flame.fill"
        case .tied:    return "equal.circle.fill"
        case .unknown: return "person.2.fill"
        }
    }

    private func leaderText(_ c: WeightChallenge, _ p: WeightChallengeEngine.Progress) -> String {
        let unit = c.scoring == .percent ? "%" : " lb"
        let margin = String(format: "%.1f", p.margin) + unit
        switch p.leader {
        case .you:     return "You're up \(margin)"
        case .friend:  return "\(c.friendDisplayName) is up \(margin)"
        case .tied:    return "Dead even"
        case .unknown: return p.friend == nil ? "Add \(c.friendDisplayName)'s weigh-in" : "Weigh in to get on the board"
        }
    }

    private func signed(_ v: Double) -> String {
        let s = String(format: "%.1f", abs(v))
        if abs(v) < 0.05 { return "0.0" }
        return v < 0 ? "−\(s)" : "+\(s)"
    }
}

// MARK: - Body state strip

struct HomeStateStrip: View {
    struct Item: Identifiable {
        var id: String { name }
        let name: String
        let score: Int
        let colors: [Color]
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                VStack(spacing: 8) {
                    ZStack {
                        NekaMiniRing(progress: Double(item.score) / 100, colors: item.colors)
                        Text(item.score > 0 ? "\(item.score)" : "–")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .contentTransition(.numericText())
                    }
                    .frame(width: 52, height: 52)
                    Text(item.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.name) \(item.score)")
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .nekaCard()
    }
}

// MARK: - Fuel

struct HomeFuelCard: View {
    let protein: Double
    let proteinTarget: Double
    let calories: Double
    let calorieTarget: Double
    var onLogMeal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Fuel")
                    .font(Neka.label)
                    .foregroundColor(Neka.ink)
                Spacer()
                Button(action: onLogMeal) {
                    Label("Log meal", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.dialedScale)
            }
            row(
                title: "Protein",
                value: "\(Int(protein)) / \(Int(proteinTarget)) g",
                progress: proteinTarget > 0 ? protein / proteinTarget : 0,
                tint: Neka.orange
            )
            row(
                title: "Calories",
                value: "\(Int(calories).formatted()) / \(Int(calorieTarget).formatted())",
                progress: calorieTarget > 0 ? calories / calorieTarget : 0,
                tint: calories > calorieTarget ? Neka.rose : Neka.green
            )
            Text(calorieNote)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .nekaCard()
    }

    private var calorieNote: String {
        let left = calorieTarget - calories
        if calories == 0 { return "Nothing logged yet today." }
        if left >= 0 { return "\(Int(left).formatted()) kcal left in today's deficit budget." }
        return "\(Int(-left).formatted()) kcal over budget — a walk claws some back."
    }

    private func row(title: String, value: String, progress: Double, tint: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
            }
            NekaProgressBar(progress: progress, tint: tint, height: 7)
        }
    }
}

// MARK: - Today's timeline

struct HomeTimelineCard: View {
    let items: [HomeTimelineItem]
    var now: Date = Date()

    private let startHour = 6.0
    private let endHour = 24.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Timeline")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                NavigationLink {
                    LazyDestination { TimelineView() }
                        .environment(\.colorScheme, .dark)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .accessibilityLabel("Open full timeline")
            }

            track
                .frame(height: 64)

            if items.isEmpty {
                Text("No plan for today yet. Build one in the Plan tab.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(visibleItems) { item in
                        row(item)
                    }
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    /// Recent + current + next — at most four rows.
    private var visibleItems: [HomeTimelineItem] {
        let recentCutoff = now.addingTimeInterval(-3 * 3600)
        let relevant = items.filter { $0.end >= recentCutoff }
        let picked = relevant.isEmpty ? Array(items.suffix(3)) : Array(relevant.prefix(4))
        return picked
    }

    private func fraction(_ date: Date) -> CGFloat {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60
        let adjusted = h < 4 ? h + 24 : h   // after-midnight still belongs to today
        return CGFloat(max(0, min(1, (adjusted - startHour) / (endHour - startHour))))
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let trackY: CGFloat = 32
            let nowX = fraction(now) * w

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: w, height: 14)
                    .offset(y: trackY - 7)

                ForEach(items) { item in
                    let x = fraction(item.start) * w
                    let x2 = max(x + 12, fraction(item.end) * w)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(item.tint.opacity(item.status == .done ? 0.55 : 0.9))
                        .frame(width: x2 - x, height: 14)
                        .offset(x: x, y: trackY - 7)
                }

                // Hour labels
                ForEach([6, 9, 12, 15, 18, 21], id: \.self) { hour in
                    Text(String(format: "%d:00", hour))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Neka.inkTertiary)
                        .fixedSize()
                        .position(x: CGFloat(Double(hour) - startHour) / CGFloat(endHour - startHour) * w + 12, y: trackY + 22)
                }

                // Now marker
                Rectangle()
                    .fill(Neka.ink)
                    .frame(width: 1.5, height: 30)
                    .position(x: nowX, y: trackY + 4)
                Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Neka.ink))
                    .fixedSize()
                    .position(x: min(max(nowX, 22), w - 22), y: 6)
            }
        }
    }

    private func row(_ item: HomeTimelineItem) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(item.tint)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                Text("\(timeString(item.start)) – \(timeString(item.end))")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
            Spacer()
            Text(item.status.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(statusColor(item.status))
        }
    }

    private func statusColor(_ s: HomeTimelineItem.Status) -> Color {
        switch s {
        case .done:     return Neka.inkTertiary
        case .active:   return Neka.blue
        case .upcoming: return Neka.inkSecondary
        case .missed:   return Neka.rose
        }
    }

    private func timeString(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

// MARK: - Coach

struct HomeCoachCard: View {
    let insights: [CoachInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Coach")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }

            if insights.isEmpty {
                Text("All caught up. Keep stacking good days.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        row(insight)
                        if index < insights.count - 1 {
                            Divider().overlay(Neka.hairline).padding(.leading, 50)
                        }
                    }
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func row(_ insight: CoachInsight) -> some View {
        let (tint, fill) = colors(insight.tone)
        return HStack(alignment: .top, spacing: 14) {
            NekaIconBadge(systemName: insight.icon, tint: tint, fill: fill)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(insight.detail)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func colors(_ tone: CoachInsight.Tone) -> (Color, Color) {
        switch tone {
        case .win:   return (Neka.green, Neka.greenSoft)
        case .nudge: return (Neka.orange, Neka.orangeSoft)
        case .info:  return (Neka.blue, Neka.blueSoft)
        case .rest:  return (Neka.lavender, Neka.lavenderSoft)
        }
    }
}
