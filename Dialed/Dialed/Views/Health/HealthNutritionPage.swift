//
//  HealthNutritionPage.swift
//  Dialed
//
//  Nutrition: calories, protein, hydration and a nutrition score up top;
//  macro balance with fiber / sugar / sodium / caffeine; insights; and a
//  meal timeline with your eating window.
//

import SwiftUI
import Charts

struct HealthNutritionPage: View {
    @ObservedObject var model: HealthDetailModel
    @EnvironmentObject private var router: AppRouter

    private var n: HealthInsights.NutritionDay { model.nutrition }

    var body: some View {
        VStack(spacing: 16) {
            hero
            tiles
            macroCard
            HealthInsightsCard(title: "Nutrition Insights", insights: insights)
            mealTimeline
        }
    }

    private var insights: [HealthInsights.Insight] {
        let hour = Double(Calendar.current.component(.hour, from: Date()))
        let expected = model.isToday ? max(0.15, min(1, (hour - 7) / 14)) : 1
        return HealthInsights.nutritionInsights(
            today: n, proteinHistory: model.proteinHistory.map(\.value),
            mealTimes: model.meals.map(\.time), expectedFraction: expected)
    }

    // MARK: - Hero

    /// Hydration as a glass you watch fill: the wave sits at your share of
    /// the goal, with the count read over the water and a one-tap refill.
    private var hero: some View {
        let scene = Neka.Scene.ice
        let progress = n.waterTargetOz > 0 ? n.waterOz / n.waterTargetOz : 0
        let glassesTarget = max(1, Int((n.waterTargetOz / 8).rounded()))
        let stats = [
            NekaStat(icon: "drop.fill", label: "Glasses", value: "\(Int(n.waterOz / 8)) of \(glassesTarget)"),
            NekaStat(icon: "flag.fill", label: "To go", value: "\(Int(max(0, n.waterTargetOz - n.waterOz))) oz"),
            NekaStat(icon: "flame.fill", label: "Calories", value: Int(n.calories).formatted())
        ]
        return VStack(alignment: .leading, spacing: 20) {
            ZStack(alignment: .topLeading) {
                NekaWaterLevel(progress: progress)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hydration")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(scene.inkSecondary)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(n.waterOz))")
                            .font(Neka.hero(64))
                            .kerning(-1.5)
                            .contentTransition(.numericText())
                        Text("oz")
                            .font(Neka.hero(28))
                    }
                    .foregroundColor(scene.ink)
                    Text("of \(Int(n.waterTargetOz)) oz goal")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(scene.ink.opacity(0.6))
                }
                .padding(20)
                .accessibilityElement(children: .combine)
            }
            .frame(height: 300)
            .background(scene.glass)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(scene.glassStroke, lineWidth: 1))
            NekaInsightPill(text: waterLine, scene: scene)
            NekaStatRow(stats: stats, scene: scene)
            if model.isToday {
                Button { router.quickLog = .water } label: { Text("Add Glass") }
                    .buttonStyle(.nekaCapsule)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var waterLine: String {
        let left = Int(max(0, n.waterTargetOz - n.waterOz))
        if left == 0 { return "Goal hit — you're well hydrated today." }
        if !model.isToday { return "Finished \(left) oz short of the goal." }
        return waterOnPace ? "On pace — \(left) oz to go today." : "A little behind pace — a glass or two now catches you up."
    }

    // MARK: - Tiles

    private var tiles: some View {
        let calLeft = n.calorieTarget - n.calories
        let score = HealthInsights.nutritionScore(n)
        return VStack(spacing: 12) {
            HealthTileGrid {
                HealthTile(
                    title: "Calories", value: Int(n.calories).formatted(), unit: "calories",
                    status: n.calories == 0 ? "Nothing logged" : (calLeft >= 0 ? "On track" : "Over budget"),
                    statusColor: calLeft >= 0 ? Neka.green : Neka.rose,
                    footnote: calLeft >= 0 ? "\(Int(calLeft).formatted()) left" : "\(Int(-calLeft).formatted()) over",
                    wash: .amber
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 0)
                        Text("of \(Int(n.calorieTarget).formatted()) calories")
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkSecondary)
                        NekaProgressBar(progress: n.calorieTarget > 0 ? min(1, n.calories / n.calorieTarget) : 0,
                                        tint: calLeft >= 0 ? Neka.orange : Neka.rose, height: 8)
                    }
                }

                HealthTile(
                    title: "Protein", value: "\(Int(n.protein))", unit: "g",
                    status: n.protein >= n.proteinTarget * 0.9 ? "Optimal" : "Below target",
                    statusColor: n.protein >= n.proteinTarget * 0.9 ? Neka.green : Neka.orange,
                    footnote: "target \(Int(n.proteinTarget)) g",
                    wash: .lime
                ) { HealthMiniBars(values: model.proteinHistory.map(\.value), tint: Neka.greenText, target: n.proteinTarget) }
            }

            HealthTile(
                title: "Nutrition Score", value: "\(score)", unit: "",
                status: HealthInsights.label(for: score),
                statusColor: score >= 70 ? Neka.green : Neka.orange,
                footnote: "estimate"
            ) {
                VStack {
                    Spacer(minLength: 0)
                    HealthScoreBar(score: score)
                }
            }
        }
    }

    private var waterOnPace: Bool {
        guard model.isToday else { return n.waterOz >= n.waterTargetOz * 0.9 }
        let hour = Double(Calendar.current.component(.hour, from: Date()))
        return n.waterOz >= n.waterTargetOz * max(0.15, min(1, (hour - 7) / 14)) - 8
    }

    // MARK: - Macros

    private struct Macro: Identifiable {
        let id: String
        let grams: Double
        let target: Double
        let kcalPerGram: Double
        let color: Color
        var kcal: Double { grams * kcalPerGram }
    }

    private var macros: [Macro] {
        let fatTarget = n.calorieTarget * 0.3 / 9
        let carbTarget = max(0, n.calorieTarget - n.proteinTarget * 4 - fatTarget * 9) / 4
        return [
            Macro(id: "Protein", grams: n.protein, target: n.proteinTarget, kcalPerGram: 4, color: Neka.green),
            Macro(id: "Carbs", grams: model.carbs, target: carbTarget, kcalPerGram: 4, color: Neka.orange),
            Macro(id: "Fat", grams: model.fat, target: fatTarget, kcalPerGram: 9, color: Color(hex: "4C6FE0"))
        ]
    }

    private var macroCard: some View {
        let totalKcal = macros.map(\.kcal).reduce(0, +)
        return VStack(alignment: .leading, spacing: 14) {
            HealthCardHeader(title: "Macro Balance")
            HStack(spacing: 16) {
                ZStack {
                    if totalKcal > 0 {
                        Chart(macros) { m in
                            SectorMark(angle: .value("calories", m.kcal), innerRadius: .ratio(0.72), angularInset: 1.5)
                                .foregroundStyle(m.color)
                                .cornerRadius(3)
                        }
                    } else {
                        Circle().stroke(Neka.track, lineWidth: 14).padding(7)
                    }
                    VStack(spacing: 0) {
                        Text(Int(n.calories).formatted())
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Neka.ink)
                        Text("calories")
                            .font(.system(size: 10))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(spacing: 10) {
                    ForEach(macros) { m in
                        VStack(spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Circle().fill(m.color).frame(width: 7, height: 7)
                                Text(m.id)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Neka.ink)
                                Spacer()
                                Text("\(Int(m.grams)) g")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Neka.ink)
                                Text("/ \(Int(m.target))")
                                    .font(.system(size: 10))
                                    .foregroundColor(Neka.inkTertiary)
                            }
                            NekaProgressBar(progress: m.target > 0 ? min(1, m.grams / m.target) : 0, tint: m.color, height: 5)
                        }
                    }
                }
            }
            if model.carbs == 0 && model.fat == 0 && n.calories > 0 {
                Text("Carbs and fat show up when a food app (MyFitnessPal, Lose It!, Cronometer) writes them to Apple Health.")
                    .font(.system(size: 10))
                    .foregroundColor(Neka.inkTertiary)
            }
            Divider().overlay(Neka.hairline)
            HStack(alignment: .top) {
                micro("Fiber", model.nutrition.fiber.map { "\(Int($0)) g" },
                      model.nutrition.fiber.map { "\(Int(min(100, $0 / 30 * 100)))% of 30 g" }, (model.nutrition.fiber ?? 0) >= 25)
                micro("Added sugar", model.sugar.map { "\(Int($0)) g" },
                      model.sugar.map { $0 <= 36 ? "Under limit" : "Over 36 g" }, (model.sugar ?? 0) <= 36)
                micro("Sodium", model.sodiumMg.map { String(format: "%.1f g", $0 / 1000) },
                      model.sodiumMg.map { $0 <= 2300 ? "Normal" : "High" }, (model.sodiumMg ?? 0) <= 2300)
                micro("Caffeine", model.caffeineMg.map { "\(Int($0)) mg" },
                      model.caffeineMg.map { $0 <= 400 ? "OK" : "High" }, (model.caffeineMg ?? 0) <= 400)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func micro(_ title: String, _ value: String?, _ status: String?, _ good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkTertiary)
                .lineLimit(1)
            Text(value ?? "--")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(value == nil ? Neka.inkTertiary : Neka.ink)
            Text(status ?? "No data")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(status == nil ? Neka.inkTertiary : (good ? Neka.green : Neka.orange))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Meal timeline

    private var mealTimeline: some View {
        let window = HealthInsights.eatingWindow(model.meals.map(\.time))
        let dayStart = Calendar.current.startOfDay(for: model.day)
        let span: (Double, Double) = (6, 24)
        func x(_ date: Date, _ width: CGFloat) -> CGFloat {
            let h = date.timeIntervalSince(dayStart) / 3600
            return CGFloat((min(span.1, max(span.0, h)) - span.0) / (span.1 - span.0)) * width
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Meal Timeline")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                if let window {
                    let hours = window.end.timeIntervalSince(window.start) / 3600
                    Text("Eating window \(window.start.formatted(date: .omitted, time: .shortened))–\(window.end.formatted(date: .omitted, time: .shortened)) · \(String(format: "%.1f", hours)) h")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Button { router.openHome(.foodLog) } label: {
                    Text("Edit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(Neka.track))
                }
                .accessibilityLabel("Open the food log")
                Button { router.quickLog = .meal } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Neka.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Neka.track))
                }
                .accessibilityLabel("Log food")
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track).frame(height: 10)
                    if let window {
                        Capsule()
                            .fill(Neka.orange.opacity(0.35))
                            .frame(width: max(10, x(window.end, w) - x(window.start, w)), height: 10)
                            .offset(x: x(window.start, w))
                    }
                    ForEach(model.meals) { meal in
                        Circle()
                            .fill(Neka.orange)
                            .overlay(Circle().stroke(Neka.surface, lineWidth: 2))
                            .frame(width: 16, height: 16)
                            .offset(x: x(meal.time, w) - 8)
                    }
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            HStack {
                ForEach([6, 12, 18], id: \.self) { h in
                    Text(healthHourLabel(h))
                    Spacer()
                }
                Text("12 AM")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Neka.inkTertiary)

            if model.meals.isEmpty {
                Text("No meals logged. Tap + to log one (photo or text — Apple Intelligence estimates it).")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            } else {
                ForEach(model.meals) { meal in
                    HStack {
                        Text(meal.time.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                            .frame(width: 70, alignment: .leading)
                        Text(meal.name)
                            .font(.system(size: 13))
                            .foregroundColor(Neka.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(meal.calories)) calories")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Neka.ink)
                    }
                }
            }
        }
        .padding(16)
        .nekaCard()
    }
}
