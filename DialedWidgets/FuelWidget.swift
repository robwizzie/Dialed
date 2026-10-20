//
//  FuelWidget.swift
//  DialedWidgets
//
//  Food at a glance: a calorie budget gauge, protein to go, today's
//  plate, and your favorite meals as one-tap buttons.
//

import AppIntents
import SwiftUI
import WidgetKit

struct DialedFuelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DialedFuelWidget", provider: DialedProvider()) { entry in
            FuelWidgetView(entry: entry)
        }
        .configurationDisplayName("Fuel")
        .description("Calories and protein left, today's meals, and your favorites one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct FuelWidgetView: View {
    let entry: DialedEntry
    @Environment(\.widgetFamily) private var family

    private var s: WidgetSnapshot { entry.today }
    private var over: Bool { s.caloriesLeft < 0 }
    private var meals: [WidgetMeal] { s.meals ?? [] }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Label(over ? "\(Fmt.int(-s.caloriesLeft)) kcal over" : "\(Fmt.int(s.caloriesLeft)) kcal left",
                      systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Gauge(value: s.calorieProgress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                Text("\(Fmt.int(s.proteinLeft)) g protein to go")
                    .font(.system(size: 12))
            }
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(WidgetLink.food.url)
        case .systemLarge:
            large
                .dialedBackground(.peach)
                .widgetURL(WidgetLink.food.url)
        case .systemMedium:
            medium
                .dialedBackground(.peach)
                .widgetURL(WidgetLink.food.url)
        default:
            small
                .dialedBackground(.peach)
                .widgetURL(WidgetLink.meal.url)
        }
    }

    // MARK: Sizes

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetTitle(icon: "flame.fill", title: "Fuel", tint: Theme.orange,
                        trailing: meals.isEmpty ? nil : "\(meals.count) meal\(meals.count == 1 ? "" : "s")")
            Spacer(minLength: 2)
            budgetGauge(width: 112)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 4)
            proteinRow
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetTitle(icon: "flame.fill", title: "Fuel", tint: Theme.orange)
                Spacer(minLength: 2)
                budgetGauge(width: 118)
                Spacer(minLength: 4)
                proteinRow
            }
            .frame(width: 128)
            favoritesGrid(rows: 2)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                budgetGauge(width: 132)
                VStack(alignment: .leading, spacing: 8) {
                    WidgetTitle(icon: "flame.fill", title: "Fuel", tint: Theme.orange,
                                trailing: Fmt.weekday(entry.date))
                    macroRow("Eaten", "\(Fmt.int(s.calories)) kcal", of: "\(Fmt.int(s.calorieTarget))",
                             progress: s.calorieProgress, tint: over ? Theme.rose : Theme.orange)
                    macroRow("Protein", "\(Fmt.int(s.protein)) g", of: "\(Fmt.int(s.proteinTarget))",
                             progress: s.proteinProgress, tint: Theme.green)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S PLATE")
                    .font(Theme.micro)
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSecondary)
                if meals.isEmpty {
                    Text("Nothing logged yet — tap a favorite below.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .widgetTile(Theme.chip, radius: 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(meals.suffix(4).enumerated()), id: \.offset) { index, meal in
                            if index > 0 { Divider().overlay(Theme.track) }
                            mealRow(meal)
                        }
                    }
                    .padding(.horizontal, 10)
                    .widgetTile(Theme.chip, radius: 12)
                }
            }

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK ADD")
                    .font(Theme.micro)
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSecondary)
                favoritesGrid(rows: 2)
                    .frame(height: 100)
            }
        }
    }

    // MARK: Pieces

    /// Half-dial: how much of today's budget is eaten, with what's left inside.
    private func budgetGauge(width: CGFloat) -> some View {
        let line = width * 0.1
        let tint = over ? Theme.rose : Theme.orange
        return ZStack(alignment: .bottom) {
            HalfArc(lineWidth: line)
                .stroke(Theme.track, style: StrokeStyle(lineWidth: line, lineCap: .round))
            HalfArc(lineWidth: line)
                .trim(from: 0, to: s.calorieProgress)
                .stroke(
                    LinearGradient(colors: [Theme.amber, tint], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
                .widgetAccentable()
                .opacity(s.calorieProgress > 0 ? 1 : 0)
            VStack(spacing: -1) {
                Text(Fmt.int(abs(s.caloriesLeft)))
                    .font(Theme.display(width * 0.2))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(over ? "kcal over" : "kcal left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(over ? Theme.roseText : Theme.orangeText)
            }
            .frame(maxWidth: width - line * 3)
        }
        .frame(width: width, height: width / 2 + line / 2)
    }

    private var proteinRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text("\(Fmt.int(s.protein))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("/ \(Fmt.int(s.proteinTarget)) g protein")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            CapsuleBar(progress: s.proteinProgress, tint: Theme.green, height: 5, pace: entry.pace)
        }
    }

    private func macroRow(_ title: String, _ value: String, of target: String, progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("/ \(target)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
            CapsuleBar(progress: progress, tint: tint, height: 6)
        }
    }

    private func mealRow(_ meal: WidgetMeal) -> some View {
        HStack(spacing: 8) {
            Text(meal.time.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 52, alignment: .leading)
            Text(meal.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(Fmt.int(meal.calories))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.orangeText)
            Text("\(Fmt.int(meal.protein))g")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.greenText)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    /// Up to four favorites as tap-to-log tiles; a "Log a meal" link fills the gaps.
    @ViewBuilder
    private func favoritesGrid(rows: Int) -> some View {
        let favorites = Array(s.favorites.prefix(rows * 2))
        if favorites.isEmpty {
            Link(destination: WidgetLink.meal.url) {
                VStack(spacing: 6) {
                    Image(systemName: "star.bubble.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                    Text("Save favorites in Dialed to log them from here")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                    ActionChip(icon: "fork.knife", text: "Log a meal", tint: Theme.orangeText,
                               fill: Theme.orangeSoft, height: 26)
                        .frame(width: 120)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetTile(Theme.chip, radius: 12)
            }
        } else {
            favoriteRows(favorites, rows: rows)
        }
    }

    private func favoriteRows(_ favorites: [WidgetFavorite], rows: Int) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        if index < favorites.count {
                            favoriteTile(favorites[index])
                        } else if index == favorites.count {
                            Link(destination: WidgetLink.meal.url) { addTile }
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func favoriteTile(_ meal: WidgetFavorite) -> some View {
        Button(intent: LogFavoriteWidgetIntent(favoriteID: meal.id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.trailing, 12)
                Text("\(Fmt.int(meal.calories)) kcal · \(Fmt.int(meal.protein)) g")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.orange)
                    .widgetAccentable()
                    .padding(6)
            }
            .widgetTile(Theme.chip, radius: 12)
        }
        .buttonStyle(.plain)
    }

    private var addTile: some View {
        VStack(spacing: 2) {
            Image(systemName: "fork.knife")
                .font(.system(size: 12, weight: .semibold))
            Text(s.favorites.isEmpty ? "Log a meal" : "Something else")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Theme.orangeText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
    }
}

/// Top half of a circle, left → right, sitting on the frame's bottom edge.
private struct HalfArc: Shape {
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2 - lineWidth / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY - lineWidth / 2), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        return path
    }
}

#Preview("Small", as: .systemSmall) { DialedFuelWidget() } timeline: { DialedEntry.preview }
#Preview("Medium", as: .systemMedium) { DialedFuelWidget() } timeline: { DialedEntry.preview }
#Preview("Large", as: .systemLarge) { DialedFuelWidget() } timeline: { DialedEntry.preview }
