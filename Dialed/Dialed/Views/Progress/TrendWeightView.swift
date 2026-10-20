//
//  TrendWeightView.swift
//  Dialed
//
//  Your real weight, minus the noise. The scale bounces with water, salt
//  and timing; the trend line moves only with what's actually changing.
//  Shows trend vs today's scale (and what the gap means), the weekly rate,
//  a 30/90-day chart of weigh-ins against the trend, and body composition
//  from a smart scale (body fat %, fat and lean mass) when Health has it.
//

import SwiftUI
import SwiftData
import Charts
import HealthKit

struct TrendWeightView: View {
    @Environment(\.modelContext) private var context
    @State private var series: [WeightChallengeEngine.DailyWeight] = []
    @State private var bodyFat: [HealthKitManager.QuantityReading] = []
    @State private var lean: [HealthKitManager.QuantityReading] = []
    @State private var range = 30
    @State private var loaded = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let last = series.last {
                    summary(last)
                    chartCard
                    composition
                    explainer
                } else if loaded {
                    empty
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Trend weight")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Summary

    private func summary(_ last: WeightChallengeEngine.DailyWeight) -> some View {
        let swing = last.pounds - last.trend
        let rate = RacePace.trendRate(series)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", last.trend))
                    .font(Neka.display(46, weight: .bold))
                    .foregroundColor(Neka.ink)
                    .contentTransition(.numericText(value: last.trend))
                Text("lb trend")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
                if let rate {
                    NekaPill(text: rate >= 0 ? "−\(String(format: "%.1f", rate)) lb/wk" : "+\(String(format: "%.1f", -rate)) lb/wk",
                             tint: rate >= 0 ? Neka.greenText : Neka.rose, fill: rate >= 0 ? Neka.greenSoft : Neka.roseSoft)
                }
            }
            HStack(spacing: 10) {
                stat("Scale", String(format: "%.1f", last.pounds),
                     calendar.isDateInToday(last.day) ? "today" : last.day.formatted(.dateTime.month(.abbreviated).day()))
                stat("Water & noise", (swing >= 0 ? "+" : "−") + String(format: "%.1f", abs(swing)), "vs trend")
                if let weekAgo = series.last(where: { $0.day <= calendar.date(byAdding: .day, value: -7, to: last.day) ?? last.day }) {
                    let change = last.trend - weekAgo.trend
                    stat("7 days", (change <= 0 ? "−" : "+") + String(format: "%.1f", abs(change)), "trend")
                }
            }
            Text(swingNote(swing))
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .nekaCard(wash: .mint)
    }

    private func swingNote(_ swing: Double) -> String {
        if swing > 1.5 { return "The scale is \(String(format: "%.1f", swing)) lb above your trend: mostly water (salt, carbs, a late meal, soreness). It washes out in a few days; the trend is the number to watch." }
        if swing < -1.5 { return "The scale is \(String(format: "%.1f", -swing)) lb under your trend: probably water too. Nice, but don't bank it yet." }
        return "Scale and trend agree. Weigh in each morning after the bathroom for the steadiest trend."
    }

    private func stat(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundColor(Neka.inkTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Neka.ink)
            Text(sub)
                .font(.system(size: 10))
                .foregroundColor(Neka.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.surface.opacity(0.75)))
    }

    // MARK: - Chart

    private var shown: [WeightChallengeEngine.DailyWeight] {
        guard let since = calendar.date(byAdding: .day, value: -range, to: calendar.startOfDay(for: Date())) else { return series }
        return series.filter { $0.day >= since }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weigh-ins vs trend")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                Picker("Range", selection: $range) {
                    Text("30 d").tag(30)
                    Text("90 d").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            let points = shown
            let low = (points.map { min($0.pounds, $0.trend) }.min() ?? 0) - 1
            let high = (points.map { max($0.pounds, $0.trend) }.max() ?? 0) + 1
            Chart {
                ForEach(points) { d in
                    PointMark(x: .value("Day", d.day), y: .value("Scale", d.pounds))
                        .foregroundStyle(Neka.inkTertiary.opacity(0.6))
                        .symbolSize(22)
                }
                ForEach(points) { d in
                    LineMark(x: .value("Day", d.day), y: .value("Trend", d.trend))
                        .foregroundStyle(Neka.green)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: low...max(high, low + 2))
            .frame(height: 200)
            Text("Dots are weigh-ins; the green line is your trend.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Body composition

    @ViewBuilder
    private var composition: some View {
        if let fat = bodyFat.last {
            let first = bodyFat.first { $0.date >= (calendar.date(byAdding: .day, value: -range, to: Date()) ?? Date()) } ?? fat
            let weightNow = weight(near: fat.date)
            let weightThen = weight(near: first.date)
            VStack(alignment: .leading, spacing: 12) {
                Text("Body composition")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                HStack(spacing: 10) {
                    compStat("Body fat", String(format: "%.1f%%", fat.value * 100),
                             change: (fat.value - first.value) * 100, unit: "%", goodWhenDown: true)
                    if let w = weightNow {
                        let fatLbs = w * fat.value
                        let fatThen = weightThen.map { $0 * first.value }
                        compStat("Fat mass", String(format: "%.1f lb", fatLbs),
                                 change: fatThen.map { fatLbs - $0 }, unit: "lb", goodWhenDown: true)
                        let leanLbs = lean.last?.value ?? w * (1 - fat.value)
                        let leanThen = weightThen.map { $0 * (1 - first.value) }
                        compStat("Lean mass", String(format: "%.1f lb", leanLbs),
                                 change: leanThen.map { leanLbs - $0 }, unit: "lb", goodWhenDown: false)
                    }
                }
                Text("From your smart scale via Apple Health, change over \(range) days. Scale body fat swings with hydration; watch the direction over weeks, not single readings.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .nekaCard()
        }
    }

    private func compStat(_ title: String, _ value: String, change: Double?, unit: String, goodWhenDown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundColor(Neka.inkTertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Neka.ink)
            if let change, abs(change) >= 0.05 {
                let good = goodWhenDown ? change < 0 : change > 0
                Text((change > 0 ? "+" : "−") + String(format: "%.1f", abs(change)) + " \(unit)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(good ? Neka.greenText : Neka.rose)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
    }

    private func weight(near date: Date) -> Double? {
        let day = calendar.startOfDay(for: date)
        return series.last(where: { $0.day <= day })?.pounds ?? series.first?.pounds
    }

    // MARK: - Explainer / empty

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Why a trend?", systemImage: "waveform.path.ecg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text("Day-to-day weight can swing 2–5 lb from water alone. Each day the trend moves a quarter of the way toward the scale, so a salty dinner barely nudges it while real fat loss shows up within a week or two.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .nekaCard()
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "scalemass")
                .font(.system(size: 34))
                .foregroundColor(Neka.inkTertiary)
            Text("No weigh-ins yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text("Step on your scale (or log a weigh-in) and your trend starts here.")
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Load

    private func load() async {
        let since = calendar.date(byAdding: .day, value: -180, to: Date()) ?? Date()
        let readings = await WeightDataSource.readings(context: context, since: since)
        let health = HealthKitManager.shared
        async let fat = try? health.fetchSamples(.bodyFatPercentage, unit: .percent(), from: since)
        async let leanMass = try? health.fetchSamples(.leanBodyMass, unit: .pound(), from: since)
        let fatReadings = await fat ?? []
        let leanReadings = await leanMass ?? []
        withAnimation(.easeOut(duration: 0.25)) {
            series = WeightChallengeEngine.dailySeries(readings)
            bodyFat = fatReadings
            lean = leanReadings
            loaded = true
        }
    }
}
