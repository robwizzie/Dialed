//
//  DialedTodayWidget.swift
//  DialedWidgets
//
//  Today at a glance on the Home Screen and Lock Screen: a water ring,
//  protein and calories left, and one-tap "+16 oz" / top-favorite
//  buttons. Reads the snapshot the app writes to the App Group, plus any
//  taps still waiting for the app, so a tap shows up immediately.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(at: Date(), preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        // One entry now and one at the next 4 AM day line, when totals reset.
        let today = WidgetBridge.logicalDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
        let rollover = calendar.date(byAdding: .hour, value: WidgetBridge.dayCutoffHour, to: tomorrow)
            ?? now.addingTimeInterval(86_400)
        let entries = [entry(at: now, preview: false), entry(at: rollover, preview: false)]
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, preview: Bool) -> TodayEntry {
        let bridge = WidgetBridge()
        guard let stored = bridge.readSnapshot() else {
            return TodayEntry(date: date, snapshot: preview ? .placeholder : .empty)
        }
        return TodayEntry(date: date, snapshot: stored.display(with: bridge.pending(), now: date))
    }
}

private extension WidgetSnapshot {
    /// Before the app has run once with the App Group.
    static var empty: WidgetSnapshot {
        WidgetSnapshot(waterOz: 0, waterTargetOz: 120, protein: 0, proteinTarget: 190,
                       calories: 0, calorieTarget: 2_200, favorites: [], updatedAt: .distantPast)
    }
}

// MARK: - Widget

struct DialedTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your Dialed score, plus water, protein and calories left. Log water or a favorite meal with a tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Palette (mirrors the app's Neka tokens)

private enum Palette {
    static func paper(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(rgb: 0x1E2125) : .white }
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(rgb: 0xF4F4F2) : Color(rgb: 0x121212) }
    static func inkSecondary(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(rgb: 0xA0A0A6) : Color(rgb: 0x6E6E73) }
    static func track(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06) }
    static func skySoft(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(rgb: 0x16293A) : Color(rgb: 0xDDF0FC) }
    static func greenSoft(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(rgb: 0x1C3324) : Color(rgb: 0xDDF3E1) }
    static let sky = Color(rgb: 0x5DB4F0)
    static let green = Color(rgb: 0x4CB868)
    static let orange = Color(rgb: 0xF59A4C)
    static let rose = Color(rgb: 0xEE7C8E)
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Views

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private var s: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            inline
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            medium
                .containerBackground(for: .widget) { Palette.paper(scheme) }
        default:
            small
                .containerBackground(for: .widget) { Palette.paper(scheme) }
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                scoreDial(size: 62)
                VStack(alignment: .leading, spacing: 4) {
                    stat(value: s.waterOz, unit: "oz", caption: "of \(Int(s.waterTargetOz)) oz water", tint: Palette.sky)
                    stat(value: s.proteinLeft, unit: "g", caption: "protein left", tint: Palette.green)
                }
            }
            Spacer(minLength: 0)
            waterButton
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                scoreDial(size: 84)
                Text("\(Int(s.waterOz.rounded())) / \(Int(s.waterTargetOz)) oz water")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.inkSecondary(scheme))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    stat(value: s.proteinLeft, unit: "g", caption: "protein left", tint: Palette.green)
                    caloriesStat
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    waterButton
                    if let top = s.favorites.first {
                        Button(intent: LogFavoriteWidgetIntent(favoriteID: top.id)) {
                            pill(icon: "star.fill", text: top.name, fill: Palette.greenSoft(scheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Today's Dialed score on the same dial as the app icon.
    private func scoreDial(size: CGFloat) -> some View {
        DialGauge(value: Double(s.dialedScore) / 100, label: "\(s.dialedScore)",
                  caption: size >= 80 ? "dialed" : nil, dark: scheme == .dark)
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dialed score \(s.dialedScore)")
    }

    private var caloriesStat: some View {
        let over = s.caloriesLeft < 0
        return stat(value: abs(s.caloriesLeft), unit: "kcal",
                    caption: over ? "over" : "left", tint: over ? Palette.rose : Palette.orange)
    }

    private func stat(value: Double, unit: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Palette.ink(scheme))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(tint)
            }
            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(Palette.inkSecondary(scheme))
                .lineLimit(1)
        }
    }

    private var waterButton: some View {
        Button(intent: AddWaterWidgetIntent(ounces: 16)) {
            pill(icon: "plus", text: "16 oz", fill: Palette.skySoft(scheme))
        }
        .buttonStyle(.plain)
    }

    private func pill(icon: String, text: String, fill: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(Palette.ink(scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(fill))
    }

    // MARK: Lock Screen

    private var circular: some View {
        Gauge(value: min(s.waterOz, max(s.waterTargetOz, 1)), in: 0...max(s.waterTargetOz, 1)) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text("\(Int(s.waterOz.rounded()))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(Int(s.waterOz.rounded())) / \(Int(s.waterTargetOz)) oz", systemImage: "drop.fill")
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()
            Gauge(value: s.waterProgress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Text("\(Int(s.proteinLeft.rounded())) g protein · \(caloriesShort)")
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var inline: some View {
        Label("\(Int(s.waterOz.rounded())) oz · \(caloriesShort)", systemImage: "drop.fill")
    }

    private var caloriesShort: String {
        s.caloriesLeft >= 0
            ? "\(Int(s.caloriesLeft.rounded())) kcal left"
            : "\(Int((-s.caloriesLeft).rounded())) kcal over"
    }
}
