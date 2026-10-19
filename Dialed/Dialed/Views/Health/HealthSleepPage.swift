//
//  HealthSleepPage.swift
//  Dialed
//
//  Sleep: score, total sleep across the last two weeks (tap a night to
//  jump to it), stages (a full hypnogram when Apple Health has stage
//  data, a stage breakdown otherwise), the night's timeline and insights.
//

import SwiftUI
import Charts

struct HealthSleepPage: View {
    @ObservedObject var model: HealthDetailModel
    @State private var scrubbedNight: Date?

    private let deepBlue = Color(hex: "4C6FE0")
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 16) {
            if let night = model.lastNight {
                scoreCard(night)
                totalCard(night)
                stagesCard(night)
                timelineCard(night)
                HealthInsightsCard(title: "Sleep Insights",
                                   insights: HealthInsights.sleepInsights(last: night, history: model.nights))
            } else {
                emptyCard
                if !model.nights.isEmpty { totalCard(nil) }
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 30))
                .foregroundColor(Neka.lavender)
            Text("No sleep recorded for this night")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text("Wear your Pixel Watch to bed and it syncs here through Google Health. Apple Health sleep data works too.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .nekaCard()
    }

    // MARK: - Score

    private func scoreCard(_ night: HealthInsights.Night) -> some View {
        let score = HealthInsights.sleepScore(night)
        return VStack(alignment: .leading, spacing: 12) {
            HealthCardHeader(title: "Sleep Score", trailing: night.vendorScore != nil ? "from your watch" : "Dialed estimate")
            HStack(alignment: .center, spacing: 10) {
                Text("\(score)")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .contentTransition(.numericText())
                NekaPill(text: HealthInsights.label(for: score), tint: .white, fill: score >= 70 ? Neka.sky : Neka.orange)
                Spacer()
            }
            HealthScoreBar(score: score)
            if night.vendorScore == nil {
                Text("Duration, time asleep in bed, deep + REM share and wake-ups.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Total sleep

    private func totalCard(_ night: HealthInsights.Night?) -> some View {
        let recent = model.nights.suffix(14)
        let avg = HealthInsights.mean(recent.filter { $0.wakeDay != night?.wakeDay }.map(\.hours))
        let scrub = scrubbedNight.flatMap { s in recent.min { abs($0.wakeDay.timeIntervalSince(s)) < abs($1.wakeDay.timeIntervalSince(s)) } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HealthCardHeader(title: "Total Sleep", trailing: "tap a night")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(night.map { String(format: "%.1f", $0.hours) } ?? "--")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text("hours")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                if let night, let avg, avg > 0 {
                    HealthDeltaChip(percent: (night.hours - avg) / avg * 100)
                }
                Spacer()
                if let avg {
                    Text(String(format: "avg %.1f h", avg))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            Chart {
                ForEach(Array(recent), id: \.wakeDay) { n in
                    BarMark(x: .value("Night", n.wakeDay, unit: .day), y: .value("Hours", n.hours), width: .ratio(0.6))
                        .foregroundStyle(calendar.isDate(n.wakeDay, inSameDayAs: model.day)
                                         ? AnyShapeStyle(LinearGradient(colors: [Neka.lavender, deepBlue], startPoint: .top, endPoint: .bottom))
                                         : AnyShapeStyle(Neka.lavender.opacity(0.35)))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", 7.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Neka.inkTertiary)
                if let scrub {
                    RuleMark(x: .value("Night", scrub.wakeDay, unit: .day))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            chartBubble("\(scrub.wakeDay.formatted(.dateTime.weekday(.abbreviated).day())) · \(String(format: "%.1f h", scrub.hours))")
                        }
                }
            }
            .chartXSelection(value: $scrubbedNight)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: [0, 4, 8]) }
            .frame(height: 130)
            .onChange(of: scrubbedNight) { old, new in
                // Lifting the finger jumps to the night you were on.
                if new == nil, let old,
                   let n = recent.min(by: { abs($0.wakeDay.timeIntervalSince(old)) < abs($1.wakeDay.timeIntervalSince(old)) }) {
                    model.day = n.wakeDay
                }
            }
        }
        .padding(16)
        .nekaCard(wash: .lavender)
    }

    // MARK: - Stages

    private func stageColor(_ stage: HealthKitManager.SleepStage) -> Color {
        switch stage {
        case .awake: return Neka.rose
        case .rem:   return Color(hex: "B9C6F7")
        case .light: return Color(hex: "7C95EC")
        case .deep:  return deepBlue
        }
    }

    private func stagesCard(_ night: HealthInsights.Night) -> some View {
        let parts = [
            StagePart(stage: .awake, minutes: night.awakeMinutes ?? max(0, night.inBedMinutes - night.asleepMinutes)),
            StagePart(stage: .rem, minutes: night.remMinutes),
            StagePart(stage: .light, minutes: night.lightMinutes),
            StagePart(stage: .deep, minutes: night.deepMinutes)
        ]
        let total = max(1, parts.compactMap(\.minutes).reduce(0, +))
        return VStack(alignment: .leading, spacing: 12) {
            HealthCardHeader(title: "Sleep Stages")
            if !model.hypnogram.isEmpty {
                hypnogram
                    .frame(height: 150)
            } else if parts.dropFirst().contains(where: { $0.minutes != nil }) {
                // No stage-by-stage data — show the night's proportions.
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts) { part in
                            if let minutes = part.minutes, minutes > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(stageColor(part.stage))
                                    .frame(width: max(4, geo.size.width * CGFloat(minutes) / CGFloat(total) - 2))
                            }
                        }
                    }
                }
                .frame(height: 22)
                Text("Your watch reports stage totals; the minute-by-minute graph needs stage data in Apple Health.")
                    .font(.system(size: 10))
                    .foregroundColor(Neka.inkTertiary)
            } else {
                Text("Your watch didn't report stages for this night.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
            HStack(alignment: .top) {
                ForEach(parts) { part in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle().fill(stageColor(part.stage)).frame(width: 8, height: 8)
                            Text(part.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Neka.inkSecondary)
                        }
                        Text(part.minutes.map(duration) ?? "--")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text(part.minutes.map { "\(Int((Double($0) / Double(total) * 100).rounded()))%" } ?? "")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Neka.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    private struct StagePart: Identifiable {
        let stage: HealthKitManager.SleepStage
        let minutes: Int?
        var id: String { stage.rawValue }
        var label: String { stage == .rem ? "REM" : stage.rawValue.capitalized }
    }

    private var hypnogram: some View {
        let order: [HealthKitManager.SleepStage] = [.awake, .rem, .light, .deep]
        return Chart(Array(model.hypnogram.enumerated()), id: \.offset) { _, seg in
            RectangleMark(
                xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                y: .value("Stage", seg.stage.rawValue == "rem" ? "REM" : seg.stage.rawValue.capitalized),
                height: .ratio(0.75)
            )
            .foregroundStyle(stageColor(seg.stage))
            .cornerRadius(2)
        }
        .chartYScale(domain: order.map { $0.rawValue == "rem" ? "REM" : $0.rawValue.capitalized })
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: - Timeline

    private func timelineCard(_ night: HealthInsights.Night) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthCardHeader(title: "Sleep Timeline")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track)
                    Capsule()
                        .fill(LinearGradient(colors: [Neka.rose.opacity(0.7), Color(hex: "7C95EC"), deepBlue, Color(hex: "B9C6F7")],
                                             startPoint: .leading, endPoint: .trailing))
                        .padding(.horizontal, geo.size.width * 0.06)
                }
            }
            .frame(height: 14)
            HStack {
                timelineStat("bed.double.fill", "Fell asleep", night.bedtime.formatted(date: .omitted, time: .shortened), Neka.rose)
                Spacer()
                timelineStat("sun.max.fill", "Woke up", night.wakeTime.formatted(date: .omitted, time: .shortened), Neka.orange)
                Spacer()
                timelineStat("clock.fill", "In bed", duration(night.inBedMinutes), Neka.sky)
            }
            HStack {
                timelineStat("percent", "Efficiency", "\(Int((night.efficiency * 100).rounded()))%", Neka.green)
                Spacer()
                timelineStat("arrow.triangle.2.circlepath", "Wake-ups", night.awakenings.map { "\($0)" } ?? "--", Neka.lavender)
                Spacer()
                timelineStat("moon.fill", "Asleep", duration(night.asleepMinutes), deepBlue)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func timelineStat(_ icon: String, _ title: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
            }
        }
        .frame(minWidth: 96, alignment: .leading)
    }
}
