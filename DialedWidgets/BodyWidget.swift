//
//  BodyWidget.swift
//  DialedWidgets
//
//  Activity and recovery from your watch and scale: steps, the daily
//  mile, sleep, HRV against your baseline, resting heart rate and the
//  weight trend, each in its own pastel tile with a week of history.
//

import SwiftUI
import WidgetKit

struct DialedBodyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DialedBodyWidget", provider: DialedProvider()) { entry in
            BodyWidgetView(entry: entry)
        }
        .configurationDisplayName("Body")
        .description("Steps, your daily mile, sleep, HRV, resting heart rate and your weight trend.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BodyWidgetView: View {
    let entry: DialedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let i = entry.insights {
                switch family {
                case .systemLarge:  large(i)
                case .systemMedium: medium(i)
                default:            small(i)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.green)
                    Text("Body")
                        .font(Theme.display(14))
                        .foregroundStyle(Theme.ink)
                    SyncHint()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .dialedBackground(.paper)
        .widgetURL(WidgetLink.body.url)
    }

    // MARK: Sizes

    private func small(_ i: WidgetInsights) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetTitle(icon: "figure.walk", title: "Steps", tint: Theme.green,
                        trailing: i.stepProgress >= 1 ? "🎉" : nil)
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                ZStack {
                    ProgressRing(progress: i.stepProgress, tint: Theme.green, lineWidth: 8, pace: entry.pace)
                    VStack(spacing: -1) {
                        Text(Fmt.compact(i.steps))
                            .font(Theme.display(17))
                            .foregroundStyle(Theme.ink)
                            .minimumScaleFactor(0.7)
                        Text("of \(Fmt.compact(i.stepGoal))")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    miniStat(icon: entry.ranToday ? "figure.run" : "figure.walk", tint: Theme.lavender,
                             value: String(format: "%.2f mi", entry.milesToday) + (entry.mileDone ? " ✓" : ""))
                    miniStat(icon: "moon.fill", tint: Theme.blue, value: i.sleepHours.map(Fmt.hours) ?? "—")
                    miniStat(icon: "waveform.path.ecg", tint: Theme.rose, value: i.hrv.map { "\(Fmt.int($0)) ms" } ?? "—")
                    miniStat(icon: "heart.fill", tint: Theme.orange, value: i.restingHR.map { "\(Fmt.int($0))" } ?? "—")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func medium(_ i: WidgetInsights) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                stepsTile(i)
                sleepTile(i)
            }
            HStack(spacing: 8) {
                hrvTile(i)
                weightTile(i)
            }
        }
    }

    private func large(_ i: WidgetInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetTitle(icon: "figure.stand", title: "Body", tint: Theme.green, trailing: Fmt.weekday(entry.date))
            HStack(spacing: 8) {
                stepsTile(i, chart: true)
                sleepTile(i, chart: true)
            }
            HStack(spacing: 8) {
                hrvTile(i)
                mileTile()
            }
            .frame(height: 78)
            weightTile(i, wide: true)
        }
    }

    // MARK: Tiles

    private func stepsTile(_ i: WidgetInsights, chart: Bool = false) -> some View {
        tile(icon: "figure.walk", title: "Steps", tint: Theme.green, wash: .mint,
             value: i.steps.formatted(), unit: nil,
             note: (i.stepProgress >= 1 ? "Goal hit" : "\(Fmt.compact(max(0, i.stepGoal - i.steps))) to go")
                + " · " + String(format: "%.1f mi", entry.milesToday) + (entry.mileDone ? " ✓" : "")) {
            if chart {
                WeekBars(values: i.stepsWeek.map(Double.init), tint: Theme.green,
                         goal: Double(i.stepGoal), today: entry.date)
            } else {
                CapsuleBar(progress: i.stepProgress, tint: Theme.green, height: 5, pace: entry.pace)
            }
        }
    }

    private func sleepTile(_ i: WidgetInsights, chart: Bool = false) -> some View {
        tile(icon: "moon.fill", title: "Sleep", tint: Theme.lavender, wash: .lavender,
             value: i.sleepHours.map { String(format: "%.1f", $0) } ?? "—", unit: "h",
             note: sleepNote(i.sleepHours)) {
            if chart {
                WeekBars(values: i.sleepWeek, tint: Theme.lavender, goal: 7, today: entry.date)
            } else {
                CapsuleBar(progress: (i.sleepHours ?? 0) / 8, tint: Theme.lavender, height: 5)
            }
        }
    }

    private func hrvTile(_ i: WidgetInsights) -> some View {
        var delta: Double?
        if let hrv = i.hrv, let baseline = i.hrvBaseline { delta = hrv - baseline }
        return tile(icon: "waveform.path.ecg", title: "HRV", tint: Theme.rose, wash: .rose,
                    value: i.hrv.map(Fmt.int) ?? "—", unit: "ms",
                    note: delta.map { abs($0) < 2 ? "At baseline" : "\(Fmt.signed($0, digits: 0)) vs usual" }) {
            EmptyView()
        }
    }

    /// The daily mile: today's distance, the streak, and the week as medals.
    private func mileTile() -> some View {
        tile(icon: entry.ranToday ? "figure.run" : "figure.walk", title: "Mile a day", tint: Theme.lavender,
             wash: .lavender, value: String(format: "%.2f", entry.milesToday), unit: "mi",
             note: entry.mileDone
                ? (entry.mileStreak > 1 ? "Done · 🔥 \(entry.mileStreak) days" : "Done today ✓")
                : String(format: "%.2f mi to go", max(0, entry.mileGoal - entry.milesToday)),
             chartBeside: true) {
            MileWeekDots(days: entry.mileWeek, goal: entry.mileGoal, size: 12)
        }
    }

    private func weightTile(_ i: WidgetInsights, wide: Bool = false) -> some View {
        tile(icon: "scalemass.fill", title: "Weight", tint: Theme.sky, wash: .sky,
             value: i.weight.map { String(format: "%.1f", $0) } ?? "—", unit: "lb",
             note: i.weightChange.map { "\(Fmt.signed($0)) lb · \(i.weightTrend.count)d trend" },
             chartBeside: true) {
            Sparkline(values: i.weightTrend, tint: Theme.sky)
                .frame(maxWidth: wide ? .infinity : 56)
        }
    }

    /// Pastel tile: icon + title, big value, a note, and an optional chart
    /// below (or beside, for the weight sparkline).
    private func tile<Chart: View>(icon: String, title: String, tint: Color, wash: Theme.Wash,
                                   value: String, unit: String?, note: String?, chartBeside: Bool = false,
                                   @ViewBuilder chart: () -> Chart) -> some View {
        let header = HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 0)
        }
        let reading = VStack(alignment: .leading, spacing: 1) {
            ValueText(value: value, unit: unit, size: 19)
            if let note {
                Text(note)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            header
            if chartBeside {
                HStack(alignment: .top, spacing: 8) {
                    reading
                    chart().frame(maxHeight: .infinity)
                }
            } else {
                reading
                chart().frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetTile(wash.tile, radius: 14)
    }

    private func miniStat(icon: String, tint: Color, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .widgetAccentable()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func sleepNote(_ hours: Double?) -> String? {
        guard let hours else { return nil }
        switch hours {
        case 8...:   return "Fully charged"
        case 7..<8:  return "Solid night"
        case 6..<7:  return "A bit short"
        default:     return "Running low"
        }
    }
}

#Preview("Small", as: .systemSmall) { DialedBodyWidget() } timeline: { DialedEntry.preview }
#Preview("Medium", as: .systemMedium) { DialedBodyWidget() } timeline: { DialedEntry.preview }
#Preview("Large", as: .systemLarge) { DialedBodyWidget() } timeline: { DialedEntry.preview }
