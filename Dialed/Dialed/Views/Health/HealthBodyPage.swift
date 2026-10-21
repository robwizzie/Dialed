//
//  HealthBodyPage.swift
//  Dialed
//
//  Body: resting heart rate, HRV, readiness and steps up top; illness
//  watch and stress from your overnight vitals; calorie
//  balance and activity by hour (drag across to read any hour); every
//  body metric with a 14-day trend you can tap open.
//

import SwiftUI
import Charts

struct HealthBodyPage: View {
    @ObservedObject var model: HealthDetailModel
    @State private var expandedMetric: String?
    // Raw chart positions while scrubbing; read through `hour(_:)`.
    @State private var balanceX: Double?
    @State private var activityX: Double?

    /// Scrub position → a valid hour index (drags past the edge clamp).
    private func hour(_ x: Double?) -> Int? {
        x.map { min(23, max(0, Int($0.rounded()))) }
    }

    private typealias DayValue = HealthInsights.DayValue

    var body: some View {
        VStack(spacing: 16) {
            tiles
            HealthStressCard(stress: model.stress)
            HealthIllnessCard(check: model.illness, isToday: model.isToday)
            calorieBalance
            MetabolismLink()
            metricsCard
            activityCard
        }
    }

    private func baseline(_ series: [DayValue]) -> [Double] {
        series.filter { $0.date < model.day }.suffix(14).map(\.value)
    }

    private func upTo(_ series: [DayValue]) -> [DayValue] {
        series.filter { $0.date <= model.day }
    }

    // MARK: - Tiles

    private var tiles: some View {
        let rhr = model.value(on: model.restingHR)
        let hrv = model.value(on: model.hrv)
        let steps = model.dailySteps.last { $0.date <= model.day }?.value ?? 0
        let stepAvg = HealthInsights.mean(model.dailySteps.filter { $0.date < model.day }.map(\.value))
        // Hoisted so the tile calls stay cheap to type-check.
        let rhrText: String = rhr.map { "\(Int($0.rounded()))" } ?? "--"
        let rhrStatus: String? = rhr.map { $0 <= 65 ? "Optimal" : ($0 <= 75 ? "Normal" : "High") }
        let rhrAvg: String? = HealthInsights.mean(baseline(model.restingHR)).map { "avg \(Int($0))" }
        let stepsDelta: Double? = stepAvg.flatMap { $0 > 0 ? (steps - $0) / $0 * 100 : nil }
        let stepsStatus: String = steps >= 10_000 ? "Goal hit" : "\(Int(max(0, 10_000 - steps)).formatted()) to go"
        let recentSteps: [Double] = model.dailySteps.filter { $0.date <= model.day }.suffix(10).map(\.value)
        return HealthTileGrid {
            HealthTile(
                title: "Resting Heart Rate", value: rhrText, unit: "bpm",
                delta: HealthInsights.percentChange(rhr, baseline: baseline(model.restingHR)), goodWhenUp: false,
                status: rhrStatus,
                statusColor: (rhr ?? 0) > 75 ? Neka.orangeText : Neka.greenText,
                footnote: rhrAvg,
                wash: .mint
            ) { HealthSparkline(values: upTo(model.restingHR), tint: Neka.green) }

            HealthTile(
                title: "HRV", value: hrv.map { "\(Int($0.rounded()))" } ?? "--", unit: "ms",
                delta: HealthInsights.percentChange(hrv, baseline: baseline(model.hrv)),
                status: hrvStatus(hrv), statusColor: Neka.skyText,
                footnote: HealthInsights.mean(baseline(model.hrv)).map { "avg \(Int($0))" },
                wash: .sky
            ) { HealthMiniBars(values: upTo(model.hrv).suffix(14).map(\.value), tint: Neka.sky) }

            HealthTile(
                title: "Readiness", value: model.readiness.map { "\($0)" } ?? "--", unit: "/100",
                status: model.readiness.map { HealthInsights.label(for: $0) } ?? "Needs HRV + sleep",
                statusColor: (model.readiness ?? 0) >= 70 ? Neka.greenText : Neka.orangeText,
                footnote: "estimate",
                wash: .lavender
            ) { readinessGauge }

            HealthTile(
                title: "Steps", value: Int(steps).formatted(), unit: "",
                delta: stepsDelta,
                status: stepsStatus,
                statusColor: steps >= 10_000 ? Neka.greenText : Neka.inkSecondary,
                wash: .peach
            ) { HealthMiniBars(values: recentSteps, tint: Neka.orange, target: 10_000) }
        }
    }

    private func hrvStatus(_ hrv: Double?) -> String? {
        guard let hrv, let avg = HealthInsights.mean(baseline(model.hrv)) else { return hrv == nil ? nil : "Building baseline" }
        if hrv >= avg * 1.05 { return "Above baseline" }
        if hrv <= avg * 0.9 { return "Below baseline" }
        return "On baseline"
    }

    private var readinessGauge: some View {
        let value = Double(model.readiness ?? 0) / 100
        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Circle()
                    .trim(from: 0.5, to: 1)
                    .stroke(Neka.track, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Circle()
                    .trim(from: 0.5, to: 0.5 + 0.5 * value)
                    .stroke(Neka.lavender, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            .frame(width: min(geo.size.width, geo.size.height * 2), height: min(geo.size.width, geo.size.height * 2))
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .offset(y: 4)
        }
    }

    // MARK: - Calorie balance

    private var calorieBalance: some View {
        let intake = model.intakeHourly.reduce(0, +)
        let nowHour = model.isToday ? Calendar.current.component(.hour, from: Date()) : 23
        let burn = model.burnHourly.prefix(nowHour + 1).reduce(0, +)
        let net = intake - burn
        let balanceHour = hour(balanceX)
        return VStack(alignment: .leading, spacing: 10) {
            HealthCardHeader(title: "Calorie Balance", trailing: model.isToday ? "so far today" : nil)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(net > 0 ? "+" : "")\(Int(net).formatted())")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text("calories")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    legend(Neka.orange, "Intake \(Int(intake).formatted())")
                    legend(Neka.green, "Burn \(Int(burn).formatted())")
                }
            }
            Text(net <= 0 ? "In a deficit — this is the direction you want." : "In a surplus so far. An hour-long walk closes ~300 calories.")
                .font(.system(size: 12))
                .foregroundColor(net <= 0 ? Neka.greenText : Neka.orangeText)

            Chart {
                // Side by side: intake just left of the hour, burn just right.
                ForEach(0..<24, id: \.self) { h in
                    BarMark(x: .value("Hour", Double(h) - 0.2), y: .value("calories", model.intakeHourly[h]), width: 4)
                        .foregroundStyle(Neka.orange)
                    BarMark(x: .value("Hour", Double(h) + 0.2), y: .value("calories", h <= nowHour ? model.burnHourly[h] : 0), width: 4)
                        .foregroundStyle(Neka.green.opacity(0.7))
                }
                if let balanceHour {
                    RuleMark(x: .value("Hour", Double(balanceHour)))
                        .foregroundStyle(Neka.ink.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            chartBubble("\(healthHourLabel(balanceHour)) · in \(Int(model.intakeHourly[balanceHour])) · out \(Int(model.burnHourly[balanceHour]))")
                        }
                }
            }
            .chartXSelection(value: $balanceX)
            .chartXScale(domain: -0.6...23.6)
            .chartXAxis { hourAxis }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 150)
        }
        .padding(16)
        .nekaCard()
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
        }
    }

    // MARK: - Body metrics

    private struct Metric: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let series: [HealthInsights.DayValue]
        let format: (Double) -> String
        let status: (Double) -> String
    }

    private var metrics: [Metric] {
        [
            Metric(id: "Skin temperature", icon: "thermometer.medium", tint: Neka.green, series: model.skinTemp,
                   format: { String(format: "%+.1f °C", $0) },
                   status: { abs($0) < 0.5 ? "Normal" : ($0 > 0 ? "Running warm" : "Running cool") }),
            Metric(id: "Respiratory rate", icon: "lungs.fill", tint: Neka.sky, series: model.respiratory,
                   format: { String(format: "%.0f rpm", $0) },
                   status: { (12...20).contains($0) ? "Normal" : "Check" }),
            Metric(id: "Blood oxygen", icon: "drop.fill", tint: Neka.orange, series: model.spO2,
                   format: { String(format: "%.0f %%", $0) },
                   status: { $0 >= 95 ? "Normal" : "Low" }),
            Metric(id: "Heart rate variability", icon: "waveform.path.ecg", tint: Neka.lavender, series: model.hrv,
                   format: { "\(Int($0.rounded())) ms" },
                   status: { _ in hrvStatus(model.value(on: model.hrv)) ?? "" }),
            Metric(id: "Weight", icon: "scalemass.fill", tint: Neka.green, series: model.weight,
                   format: { String(format: "%.1f lb", $0) },
                   status: { _ in weightTrend })
        ]
    }

    private var weightTrend: String {
        let s = upTo(model.weight)
        guard let first = s.first, let last = s.last, s.count >= 2 else { return "Weigh in to see a trend" }
        let diff = last.value - first.value
        return String(format: "%@%.1f lb in %ld days", diff <= 0 ? "−" : "+", abs(diff),
                      Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0)
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HealthCardHeader(title: "Body Metrics", trailing: "tap for 14 days")
                .padding(.bottom, 6)
            ForEach(metrics) { m in
                let current = model.value(on: m.series)
                let expanded = expandedMetric == m.id
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        expandedMetric = expanded ? nil : m.id
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: m.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(m.tint)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(m.tint.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.id)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Neka.ink)
                            Text(current.map(m.status) ?? "No data")
                                .font(.system(size: 11))
                                .foregroundColor(Neka.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        HealthSparkline(values: upTo(m.series), tint: m.tint)
                            .frame(width: 64, height: 26)
                            .opacity(expanded ? 0 : 1)
                        Text(current.map(m.format) ?? "--")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .frame(minWidth: 64, alignment: .trailing)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Neka.inkTertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    HealthTrendChart(series: upTo(m.series), tint: m.tint, format: m.format)
                        .frame(height: 140)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if m.id != metrics.last?.id { Divider().overlay(Neka.hairline) }
            }
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Activity

    private var activityCard: some View {
        let total = model.stepsHourly.reduce(0, +)
        let peak = model.stepsHourly.enumerated().max { $0.element < $1.element }
        let activityHour = hour(activityX)
        return VStack(alignment: .leading, spacing: 10) {
            HealthCardHeader(title: "Activity Level", trailing: "steps by hour")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Int(total).formatted())
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text("steps")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
                if let peak, peak.element > 0 {
                    Text("Most active \(healthHourLabel(peak.offset))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            Chart {
                ForEach(0..<24, id: \.self) { h in
                    BarMark(x: .value("Hour", Double(h)), y: .value("Steps", model.stepsHourly[h]), width: 8)
                        .foregroundStyle(h == activityHour ? Neka.green : Neka.green.opacity(0.45))
                        .cornerRadius(3)
                }
                if let activityHour {
                    RuleMark(x: .value("Hour", Double(activityHour)))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            chartBubble("\(healthHourLabel(activityHour)) · \(Int(model.stepsHourly[activityHour]).formatted()) steps")
                        }
                }
            }
            .chartXSelection(value: $activityX)
            .chartXScale(domain: -0.6...23.6)
            .chartXAxis { hourAxis }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 140)
            if total == 0 {
                Text("No hourly steps in Apple Health for this day. Your Pixel Watch's daily total still counts on Home.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private var hourAxis: some AxisContent {
        AxisMarks(values: [0.0, 6, 12, 18, 23]) { v in
            AxisValueLabel {
                if let h = v.as(Double.self) { Text(healthHourLabel(Int(h))) }
            }
        }
    }
}

/// Dark rounded label shown above a scrubbed chart point.
func chartBubble(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(hex: "17181B")))
}

/// 14-day line with an average rule; drag to read a day.
struct HealthTrendChart: View {
    let series: [HealthInsights.DayValue]
    var tint: Color = Neka.green
    var format: (Double) -> String = { String(format: "%.1f", $0) }
    @State private var selected: Date?

    var body: some View {
        if series.count < 2 {
            Text("Not enough readings yet for a trend.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let avg = HealthInsights.mean(series.map(\.value)) ?? 0
            let point = selected.flatMap { s in series.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }
            Chart {
                ForEach(series, id: \.date) { v in
                    LineMark(x: .value("Day", v.date), y: .value("Value", v.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(tint)
                    PointMark(x: .value("Day", v.date), y: .value("Value", v.value))
                        .foregroundStyle(tint)
                        .symbolSize(18)
                }
                RuleMark(y: .value("Average", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Neka.inkTertiary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(format(avg))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Neka.inkTertiary)
                    }
                if let point {
                    RuleMark(x: .value("Day", point.date))
                        .foregroundStyle(Neka.ink.opacity(0.3))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            chartBubble("\(point.date.formatted(.dateTime.month(.abbreviated).day())) · \(format(point.value))")
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        }
    }
}
