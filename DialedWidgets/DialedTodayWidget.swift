//
//  DialedTodayWidget.swift
//  DialedWidgets
//
//  Today at a glance: your Dialed score on the brand dial, water, protein
//  and calories against pace, today's mood, and one-tap logging. Large adds steps, sleep, HRV and the
//  weight trend; the Lock Screen gets a water gauge and a one-line recap.
//

import AppIntents
import SwiftUI
import WidgetKit

struct DialedTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.widgetKind, provider: DialedProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your Dialed score, plus water, protein and calories left. Log water or a favorite meal with a tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: DialedEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private var s: WidgetSnapshot { entry.today }
    /// The Dialed score, including today's mile once Home has published it.
    private var dialed: Int { s.dialedScore(miles: entry.mile != nil ? entry.milesToday : entry.insights?.miles) }
    private var score: WidgetInsights.Score? { entry.insights?.score }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(WidgetLink.water.url)
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(WidgetLink.home.url)
        case .accessoryInline:
            inline
                .containerBackground(for: .widget) { Color.clear }
        case .systemLarge:
            large
                .dialedBackground(.paper)
                .widgetURL(WidgetLink.home.url)
        case .systemMedium:
            medium
                .dialedBackground(.paper)
                .widgetURL(WidgetLink.home.url)
        default:
            small
                .dialedBackground(.paper)
                .widgetURL(WidgetLink.home.url)
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: true)
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                dial(size: 66)
                VStack(alignment: .leading, spacing: 3) {
                    legend(Theme.water, Fmt.int(s.waterOz), "oz")
                    legend(Theme.protein, Fmt.int(s.protein), "g")
                    legend(Theme.calories, Fmt.compact(Int(abs(s.caloriesLeft).rounded())),
                           s.caloriesLeft < 0 ? "over" : "left")
                    legend(Theme.lavender, String(format: "%.1f", entry.milesToday),
                           entry.mileDone ? "mi ✓" : "mi")
                }
            }
            Spacer(minLength: 6)
            waterButton(16, height: 28)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            dial(size: 112)
            VStack(alignment: .leading, spacing: 0) {
                header(compact: false)
                Spacer(minLength: 4)
                VStack(spacing: 5) {
                    metricRow("Water", value: "\(Fmt.int(s.waterOz))/\(Fmt.int(s.waterTargetOz)) oz",
                              progress: s.waterProgress, tint: Theme.water, pace: entry.pace)
                    metricRow("Protein", value: "\(Fmt.int(s.protein))/\(Fmt.int(s.proteinTarget)) g",
                              progress: s.proteinProgress, tint: Theme.protein, pace: entry.pace)
                    metricRow("Calories", value: caloriesShort,
                              progress: s.calorieProgress, tint: s.caloriesLeft < 0 ? Theme.rose : Theme.calories)
                    metricRow(entry.mileDone ? "Mile ✓" : "Mile", value: mileValue,
                              progress: entry.milesToday / max(0.1, entry.mileGoal), tint: Theme.lavender)
                }
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    waterButton(16, height: 28)
                    favoriteButton(height: 28)
                }
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.weekday(entry.date))
                        .font(Theme.micro)
                        .foregroundStyle(Theme.inkSecondary)
                        .tracking(0.6)
                    Text(score?.title ?? "Today")
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.ink)
                    if let tagline = score?.tagline {
                        Text(tagline)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let score {
                    MoodFace(avatar: entry.avatar, emoji: score.emoji,
                             accent: Color(hexString: score.accentHex), size: 50)
                }
            }

            HStack(spacing: 16) {
                dial(size: 112)
                VStack(spacing: 9) {
                    metricRow("Water", value: "\(Fmt.int(s.waterOz))/\(Fmt.int(s.waterTargetOz)) oz",
                              progress: s.waterProgress, tint: Theme.water, pace: entry.pace)
                    metricRow("Protein", value: "\(Fmt.int(s.protein))/\(Fmt.int(s.proteinTarget)) g",
                              progress: s.proteinProgress, tint: Theme.protein, pace: entry.pace)
                    metricRow("Calories", value: caloriesShort,
                              progress: s.calorieProgress, tint: s.caloriesLeft < 0 ? Theme.rose : Theme.calories)
                    metricRow(entry.mileDone ? "Mile ✓" : "Mile", value: mileValue,
                              progress: entry.milesToday / max(0.1, entry.mileGoal), tint: Theme.lavender)
                }
            }

            if let i = entry.insights {
                HStack(spacing: 8) {
                    miniTile(icon: entry.ranToday ? "figure.run" : "figure.walk", title: "Mile a day",
                             tint: Theme.lavender, wash: .lavender,
                             value: String(format: "%.2f", entry.milesToday), unit: "mi",
                             note: entry.mileStreak > 0 ? "🔥 \(entry.mileStreak) days · \(Fmt.compact(i.steps)) steps"
                                                       : "\(Fmt.compact(i.steps)) steps") {
                        MileWeekDots(days: entry.mileWeek, goal: entry.mileGoal, size: 11, showsDays: false)
                    }
                    miniTile(icon: "moon.fill", title: "Sleep", tint: Theme.blue, wash: .sky,
                             value: i.sleepHours.map { String(format: "%.1f", $0) } ?? "—", unit: "h",
                             note: i.sleepHours.map { $0 >= 7 ? "Solid night" : "A bit short" }) {
                        WeekBars(values: i.sleepWeek, tint: Theme.blue, goal: 7, showsDays: false, today: entry.date)
                    }
                    miniTile(icon: "scalemass.fill", title: "Weight", tint: Theme.sky, wash: .paper,
                             value: i.weight.map { String(format: "%.1f", $0) } ?? "—", unit: "lb",
                             note: i.weightChange.map { "\(Fmt.signed($0)) lb" }) {
                        Sparkline(values: i.weightTrend, tint: Theme.sky)
                    }
                }
                .frame(height: 104)
            } else {
                SyncHint(text: "Open Dialed to add steps, sleep and weight")
                    .frame(maxWidth: .infinity, minHeight: 104)
            }

            Spacer(minLength: 0)
            HStack(spacing: 6) {
                waterButton(8, height: 32)
                waterButton(16, height: 32)
                favoriteButton(height: 32)
                Link(destination: WidgetLink.meal.url) {
                    ActionChip(icon: "fork.knife", text: "Meal", tint: Theme.orangeText,
                               fill: Theme.orangeSoft, height: 32)
                }
            }
        }
    }

    // MARK: Pieces

    private func header(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Text(compact ? "Today" : Fmt.weekday(entry.date))
                .font(.system(size: compact ? 13 : 11, weight: .semibold))
                .foregroundStyle(compact ? Theme.ink : Theme.inkSecondary)
                .tracking(compact ? 0 : 0.6)
            Spacer(minLength: 2)
            if let score {
                HStack(spacing: 3) {
                    Text(score.emoji).font(.system(size: 11))
                    if !compact {
                        Text(score.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(hexString: score.accentHex).opacity(0.2)))
            }
        }
    }

    /// Today's Dialed score on the same dial as the app icon and the Home card.
    private func dial(size: CGFloat) -> some View {
        DialGauge(value: Double(dialed) / 100, label: "\(dialed)",
                  caption: size >= 80 ? "dialed" : nil, dark: scheme == .dark)
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dialed score \(dialed)")
    }

    private func legend(_ tint: Color, _ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Circle().fill(tint).frame(width: 7, height: 7).widgetAccentable()
            Text(value)
                .font(Theme.display(15))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(unit)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func metricRow(_ title: String, value: String, progress: Double, tint: Color, pace: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            CapsuleBar(progress: progress, tint: tint, height: 5, pace: pace)
        }
    }

    private func miniTile<Chart: View>(icon: String, title: String, tint: Color, wash: Theme.Wash,
                                       value: String, unit: String?, note: String?,
                                       @ViewBuilder chart: () -> Chart) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 0)
            }
            ValueText(value: value, unit: unit, size: 18)
            Text(note ?? " ")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            chart()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.top, 2)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetTile(wash.tile, radius: 14)
    }

    private func waterButton(_ ounces: Double, height: CGFloat) -> some View {
        Button(intent: AddWaterWidgetIntent(ounces: ounces)) {
            ActionChip(icon: "drop.fill", text: "+\(Fmt.int(ounces)) oz", tint: Theme.skyText,
                       fill: Theme.skySoft, height: height)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func favoriteButton(height: CGFloat) -> some View {
        if let top = s.favorites.first {
            Button(intent: LogFavoriteWidgetIntent(favoriteID: top.id)) {
                ActionChip(icon: "star.fill", text: top.name, tint: Theme.greenText,
                           fill: Theme.greenSoft, height: height)
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: WidgetLink.meal.url) {
                ActionChip(icon: "plus", text: "Log meal", tint: Theme.greenText,
                           fill: Theme.greenSoft, height: height)
            }
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        Gauge(value: min(s.waterOz, max(s.waterTargetOz, 1)), in: 0...max(s.waterTargetOz, 1)) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text(Fmt.int(s.waterOz))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                Text("\(Fmt.int(s.waterOz))/\(Fmt.int(s.waterTargetOz)) oz")
                Spacer(minLength: 2)
                Label("\(dialed)", systemImage: "gauge.with.dots.needle.67percent")
            }
            .font(.system(size: 13, weight: .semibold))
            .widgetAccentable()
            Gauge(value: s.waterProgress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Text("\(entry.mileDone ? "✓" : "") \(String(format: "%.1f", entry.milesToday)) mi · \(Fmt.int(s.proteinLeft)) g · \(caloriesShort)")
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var inline: some View {
        Label("\(Fmt.int(s.waterOz)) oz · \(String(format: "%.1f", entry.milesToday)) mi · \(caloriesShort)", systemImage: "drop.fill")
    }

    /// "0.62/1 mi · 🔥3".
    private var mileValue: String {
        entry.mileStreak > 1 ? "\(entry.mileShort) · 🔥\(entry.mileStreak)" : entry.mileShort
    }

    private var caloriesShort: String {
        s.caloriesLeft >= 0
            ? "\(Fmt.int(s.caloriesLeft)) kcal left"
            : "\(Fmt.int(-s.caloriesLeft)) kcal over"
    }
}

#Preview("Small", as: .systemSmall) { DialedTodayWidget() } timeline: { DialedEntry.preview }
#Preview("Medium", as: .systemMedium) { DialedTodayWidget() } timeline: { DialedEntry.preview }
#Preview("Large", as: .systemLarge) { DialedTodayWidget() } timeline: { DialedEntry.preview }
