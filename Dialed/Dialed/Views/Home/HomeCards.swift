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
                NekaIconBadge(systemName: "flag.2.crossed.fill", tint: Neka.orange, fill: Neka.surface.opacity(0.8), size: 46)
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
                    tint: Neka.ink, fill: Neka.surface.opacity(0.85)
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
    /// Opens the food log (see and edit everything eaten today).
    var onOpenLog: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Fuel")
                    .font(Neka.label)
                    .foregroundColor(Neka.ink)
                Spacer()
                Button(action: onOpenLog) {
                    Label("Food log", systemImage: "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
                Button(action: onLogMeal) {
                    Label("Log meal", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Neka.track))
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
                        .background(Circle().fill(Neka.track))
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
                    .fill(Neka.track)
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
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Neka.onInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Neka.ink))
                    .fixedSize()
                    .position(x: min(max(nowX, 32), w - 32), y: 6)
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
        d.formatted(date: .omitted, time: .shortened)
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

// MARK: - Future you

/// Where your current trend lands you on your goal day, with your
/// "future you" avatar (or your photo until one exists).
struct HomeFutureYouCard: View {
    let event: GoalEvent?
    let projection: WeightChallengeEngine.Projection?
    let image: UIImage?
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                portrait
                VStack(alignment: .leading, spacing: 4) {
                    Text("FUTURE YOU")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    if let event {
                        Text("\(event.name) · \(event.date.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .lineLimit(1)
                        if let p = projection {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(String(format: "%.1f", p.weight))
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundColor(Neka.ink)
                                Text("lb")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Neka.inkSecondary)
                                NekaPill(
                                    text: String(format: "%@%.1f", p.change <= 0 ? "−" : "+", abs(p.change)),
                                    tint: p.change <= 0 ? Neka.green : Neka.rose,
                                    fill: p.change <= 0 ? Neka.greenSoft : Neka.roseSoft
                                )
                            }
                            Text("\(event.daysAway()) days away · if you keep this pace")
                                .font(.system(size: 11))
                                .foregroundColor(Neka.inkSecondary)
                        } else {
                            Text("Weigh in a few more mornings to see where you'll land.")
                                .font(.system(size: 12))
                                .foregroundColor(Neka.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("Set your goal day")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text("The wedding, a trip, a beach day — see where your trend lands you.")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(14)
            .nekaCard(wash: .lavender)
        }
        .buttonStyle(.dialedScale)
    }

    private var portrait: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Neka.surface)
            if let image {
                FocusedImage(image: image, anchorY: 0.42)
            } else {
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Neka.lavender)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Neka.cardStroke, lineWidth: 1))
    }
}

// MARK: - If every day were like…

/// Where your weight lands on the goal day if every day from now on
/// looked like one of your recent days. Green = losing, red = gaining.
struct HomePathsCard: View {
    let scenarios: [PathProjection.Scenario]
    let targetDate: Date?
    let eventName: String?

    private var targetLabel: String {
        guard let targetDate else { return "in 30 days" }
        let day = targetDate.formatted(.dateTime.month(.abbreviated).day())
        return eventName.map { "by \($0.lowercased()) · \(day)" } ?? "by \(day)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("If every day were like…")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                Text(targetLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
                    .lineLimit(1)
            }

            ForEach(scenarios) { s in
                row(s)
                if s.id != scenarios.last?.id {
                    Divider().overlay(Neka.hairline)
                }
            }

            if !scenarios.contains(where: { $0.kind != .plan }) {
                Text("Log your meals for a couple of days (or let your food app write to Apple Health) to see where your real days lead.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Estimate: calories eaten minus calories your watch says you burned, at ~3,500 kcal per pound.")
                .font(.system(size: 10))
                .foregroundColor(Neka.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .nekaCard()
    }

    private func row(_ s: PathProjection.Scenario) -> some View {
        let flat = abs(s.poundsChange) < 0.3
        let tint = flat ? Neka.inkSecondary : (s.losing ? Neka.green : Neka.rose)
        let fill = flat ? Neka.track : (s.losing ? Neka.greenSoft : Neka.roseSoft)
        let icon = flat ? "arrow.right" : (s.losing ? "arrow.down.right" : "arrow.up.right")
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(fill))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(s.detail)
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(flat ? "±0 lb" : String(format: "%@%.1f lb", s.losing ? "−" : "+", abs(s.poundsChange)))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(tint)
                Text(String(format: "%.1f lb", s.projectedWeight))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dialed today

/// Today's Dialed score on the same dial as the app icon: the knob turns
/// as water, protein, calories and your daily mile come in. Same score the widget shows.
struct HomeDialedTodayCard: View {
    let waterOz: Double
    let waterTarget: Double
    let protein: Double
    let proteinTarget: Double
    let calories: Double
    let calorieTarget: Double
    var miles: Double = 0
    var onLogWater: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var shown: Double = 0

    private var score: Int {
        DialedScore.compute(waterOz: waterOz, waterTargetOz: waterTarget, protein: protein,
                            proteinTarget: proteinTarget, calories: calories, calorieTarget: calorieTarget,
                            miles: miles)
    }

    var body: some View {
        HStack(spacing: 18) {
            DialGauge(value: shown, label: "\(score)", caption: "dialed", dark: scheme == .dark)
                .frame(width: 118, height: 118)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Dialed score \(score) out of 100")

            VStack(alignment: .leading, spacing: 10) {
                Text("Dialed today")
                    .font(Neka.label)
                    .foregroundColor(Neka.ink)
                part("drop.fill", "Water", "\(Int(waterOz)) / \(Int(waterTarget)) oz",
                     done: waterOz >= waterTarget, tint: Neka.sky)
                part("bolt.fill", "Protein", "\(Int(protein)) / \(Int(proteinTarget)) g",
                     done: protein >= proteinTarget, tint: Neka.green)
                part("flame.fill", "Calories",
                     calories > calorieTarget ? "\(Int(calories - calorieTarget)) over" : "\(Int(max(0, calorieTarget - calories))) left",
                     done: calories > 0 && calories <= calorieTarget, tint: Neka.orange)
                part("figure.walk", "Mile", String(format: "%.2f / 1 mi", miles),
                     done: MileADay.isDone(miles), tint: Neka.lavender)
                Button(action: onLogWater) {
                    Label("Turn up water", systemImage: "dial.medium")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .nekaCard()
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.15)) { shown = Double(score) / 100 } }
        .onChange(of: score) { _, new in withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { shown = Double(new) / 100 } }
    }

    private func part(_ icon: String, _ title: String, _ value: String, done: Bool, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.ink)
                .monospacedDigit()
        }
    }
}

// MARK: - Mile a day

/// The daily mile, walked or run: a little road you travel along as the
/// distance comes in from Apple Health, a finish flag, your streak, and
/// the week as a row of medals.
struct HomeMileCard: View {
    let miles: Double
    let week: [Double]
    let streak: Int
    let ran: Bool

    @State private var shown: Double = 0
    @State private var cheer = false

    private var done: Bool { MileADay.isDone(miles) }
    private var progress: Double { min(1, miles / MileADay.goal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mile a day")
                    .font(Neka.label)
                    .foregroundColor(Neka.ink)
                Spacer()
                if streak > 0 {
                    Label("\(streak) day\(streak == 1 ? "" : "s")", systemImage: "flame.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Neka.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Neka.orangeSoft))
                        .scaleEffect(cheer ? 1.12 : 1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", miles))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(Neka.ink)
                    .contentTransition(.numericText(value: miles))
                Text("/ 1 mi")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
                if done {
                    Image(systemName: ran ? "figure.run" : "figure.walk")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(7)
                        .background(Circle().fill(Neka.green))
                        .accessibilityLabel(ran ? "Ran" : "Walked")
                }
            }

            road

            Text(MileADay.message(miles: miles, streak: streak, ran: ran))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.inkSecondary)

            weekRow
        }
        .padding(16)
        .nekaCard()
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.2)) { shown = progress }
            if done { celebrate() }
        }
        .onChange(of: progress) { old, new in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { shown = new }
            if new >= 1, old < 1 { celebrate() }
        }
    }

    /// A road with a dashed centre line; you ride the front edge toward a
    /// finish flag.
    private var road: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = 14 + (w - 28) * shown
            ZStack(alignment: .leading) {
                Capsule().fill(Neka.track).frame(height: 16)
                Capsule()
                    .fill(LinearGradient(colors: [Neka.green, Neka.sky], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(16, x + 8), height: 16)
                // Lane markings.
                Path { p in
                    p.move(to: CGPoint(x: 10, y: 8))
                    p.addLine(to: CGPoint(x: w - 10, y: 8))
                }
                .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 7]))
                .frame(height: 16)

                Image(systemName: "flag.checkered")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(done ? Neka.green : Neka.inkTertiary)
                    .offset(x: w - 22, y: -18)

                Image(systemName: ran ? "figure.run" : "figure.walk")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(done ? Neka.green : Neka.ink))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .scaleEffect(cheer ? 1.18 : 1)
                    .offset(x: x - 15)
            }
            .frame(height: 30)
        }
        .frame(height: 34)
        .padding(.top, 10)
    }

    private var weekRow: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let todayIndex = Calendar.current.component(.weekday, from: Date()) - 1
        return HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { i, m in
                let dayIndex = (todayIndex - (week.count - 1 - i) + 7 * 2) % 7
                let isToday = i == week.count - 1
                VStack(spacing: 5) {
                    ZStack {
                        Circle().stroke(Neka.track, lineWidth: 3)
                        if MileADay.isDone(m) {
                            Circle().fill(Neka.green)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white)
                        } else {
                            Circle()
                                .trim(from: 0, to: min(1, m))
                                .stroke(Neka.sky, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(isToday ? Neka.ink.opacity(0.5) : .clear, lineWidth: 1).padding(-3))
                    Text(symbols[dayIndex])
                        .font(.system(size: 10, weight: isToday ? .bold : .medium))
                        .foregroundColor(isToday ? Neka.ink : Neka.inkTertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(symbols[dayIndex]): \(String(format: "%.1f", m)) miles")
            }
        }
    }

    private func celebrate() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { cheer = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { cheer = false }
        }
    }
}
