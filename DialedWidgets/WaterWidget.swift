//
//  WaterWidget.swift
//  DialedWidgets
//
//  A bottle that fills as you drink, whether you're on pace for the time
//  of day, the week so far, and pour buttons (sizes picked in the widget's
//  settings) that log without opening the app.
//

import AppIntents
import SwiftUI
import WidgetKit

struct DialedWaterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DialedWaterWidget", intent: WaterWidgetConfiguration.self,
                               provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
        }
        .configurationDisplayName("Water")
        .description("Watch the bottle fill and log a pour with a tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct WaterWidgetView: View {
    let entry: DialedEntry
    @Environment(\.widgetFamily) private var family

    private var s: WidgetSnapshot { entry.today }
    private var pours: [Double] { entry.water.amounts }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: s.waterProgress) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(Fmt.int(s.waterOz))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            .widgetURL(WidgetLink.water.url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Label("\(Fmt.int(s.waterOz)) of \(Fmt.int(s.waterTargetOz)) oz", systemImage: "drop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Gauge(value: s.waterProgress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                Text(entry.waterStatus.text)
                    .font(.system(size: 12))
            }
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(WidgetLink.water.url)
        case .systemMedium:
            medium
                .dialedBackground(.sky)
                .widgetURL(WidgetLink.water.url)
        default:
            small
                .dialedBackground(.sky)
                .widgetURL(WidgetLink.water.url)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                WaterBottle(progress: s.waterProgress)
                    .frame(width: 44, height: 82)
                VStack(alignment: .leading, spacing: 3) {
                    ValueText(value: Fmt.int(s.waterOz), unit: "oz", size: 30)
                    Text("of \(Fmt.int(s.waterTargetOz)) oz")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    status
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(pours.prefix(2), id: \.self) { pourButton($0) }
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            WaterBottle(progress: s.waterProgress)
                .frame(width: 58, height: 118)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    ValueText(value: Fmt.int(s.waterOz), unit: "/ \(Fmt.int(s.waterTargetOz)) oz", size: 30)
                    Spacer(minLength: 4)
                    status
                }
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let week = entry.insights?.waterWeek, !week.isEmpty {
                    WeekBars(values: weekWithToday(week), tint: Theme.sky, goal: s.waterTargetOz, today: entry.date)
                        .frame(height: 40)
                } else {
                    CapsuleBar(progress: s.waterProgress, tint: Theme.sky, height: 8, pace: entry.pace)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    ForEach(pours, id: \.self) { pourButton($0) }
                }
            }
        }
    }

    private var status: some View {
        let status = entry.waterStatus
        return StatusPill(text: status.text, icon: status.icon,
                          tint: status.onTrack ? Theme.skyText : Theme.orangeText,
                          fill: status.onTrack ? Theme.skySoft : Theme.orangeSoft)
    }

    private var subtitle: String {
        if s.waterProgress >= 1 { return "Fully hydrated — nice work" }
        let glasses = Int((s.waterLeftOz / 8).rounded(.up))
        return "\(Fmt.int(s.waterLeftOz)) oz to go · about \(glasses) glass\(glasses == 1 ? "" : "es")"
    }

    /// The published week ends at Home's last refresh; today's bar uses the
    /// live total so widget taps show up there too.
    private func weekWithToday(_ week: [Double]) -> [Double] {
        Array(week.dropLast()) + [s.waterOz]
    }

    private func pourButton(_ ounces: Double) -> some View {
        Button(intent: AddWaterWidgetIntent(ounces: ounces)) {
            ActionChip(icon: "plus", text: "\(Fmt.int(ounces)) oz", tint: Theme.skyText, fill: Theme.chip)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Small", as: .systemSmall) { DialedWaterWidget() } timeline: { DialedEntry.preview }
#Preview("Medium", as: .systemMedium) { DialedWaterWidget() } timeline: { DialedEntry.preview }
