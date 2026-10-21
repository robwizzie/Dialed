//
//  HealthSleepPage.swift
//  Dialed
//
//  Sleep: score, tonight's bedtime plan, total sleep across the last two
//  weeks (tap a night to jump to it), stages (a full-night hypnogram when
//  the watch or Apple Health has stage data, a breakdown otherwise), the
//  night's real timeline — split nights included — and insights.
//

import SwiftUI
import Charts

struct HealthSleepPage: View {
    @ObservedObject var model: HealthDetailModel
    @State private var scrubbedNight: Date?
    @State private var scrubbedTime: Date?
    @State private var explaining: HealthInsights.Night?

    private let deepBlue = Color(hex: "4C6FE0")
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 16) {
            if let night = model.lastNight {
                scoreCard(night)
                if model.isToday, let tonight = tonightPlan { tonightCard(tonight) }
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
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep Score")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                Button { explaining = night } label: {
                    Label("Dialed vs Google", systemImage: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .center, spacing: 10) {
                Text("\(score)")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .contentTransition(.numericText())
                NekaPill(text: HealthInsights.label(for: score), tint: .white, fill: score >= 70 ? Neka.skyText : Neka.orangeText)
                Spacer()
                if let google = night.vendorScore {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Google")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Neka.inkTertiary)
                        Text("\(google)")
                            .font(.system(size: 17, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
            }
            HealthScoreBar(score: score)
            Text("Duration, time asleep in bed, deep + REM share and wake-ups.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .nekaCard()
        .sheet(item: Binding(get: { explaining.map { ExplainTarget(night: $0) } }, set: { explaining = $0?.night })) { target in
            SleepScoreExplainer(night: target.night)
                .presentationDetents([.large])
        }
    }

    private struct ExplainTarget: Identifiable {
        let night: HealthInsights.Night
        var id: Date { night.wakeDay }
    }

    // MARK: - Tonight

    /// Wake from your wake-up schedule when you've set one, else your usual
    /// from the last week; bedtime pays back a capped slice of sleep debt.
    private var tonightPlan: SleepVisuals.Tonight? {
        SleepVisuals.tonight(schedule: WakeSchedule.load(),
                             learnedWakeMinutes: model.sleepPlan?.wakeMinutes,
                             debtHours: model.sleepPlan?.debtHours ?? 0)
    }

    private func tonightCard(_ t: SleepVisuals.Tonight) -> some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TONIGHT")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.65))
                        Text("Be asleep by")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text(t.bedtime.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                        Text(SleepVisuals.countdown(t, now: now))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "FFD38A"))
                    }
                    Spacer()
                    Label(t.wake.formatted(date: .omitted, time: .shortened),
                          systemImage: t.fromSchedule ? "alarm.fill" : "sun.horizon.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.16)))
                        .padding(.top, 26)
                }

                NightArc(tonight: t, now: now)
                    .frame(height: 86)

                HStack(spacing: 8) {
                    nightStat("Wind down", t.windDown.formatted(date: .omitted, time: .shortened), "sparkles")
                    nightStat("Sleep", hoursText(t.targetHours), "bed.double.fill")
                    nightStat(t.fromSchedule ? "Alarm" : "Usual wake", t.wake.formatted(date: .omitted, time: .shortened),
                              t.fromSchedule ? "alarm.fill" : "sun.max.fill")
                }

                Text(debtLine(t))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(NightSky(debtHours: t.debtHours))
            .clipShape(RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tonight: be asleep by \(t.bedtime.formatted(date: .omitted, time: .shortened)), \(t.fromSchedule ? "alarm" : "wake") at \(t.wake.formatted(date: .omitted, time: .shortened))")
    }

    private func nightStat(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 8.5, weight: .heavy))
                .tracking(0.4)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.1)))
    }

    private func hoursText(_ hours: Double) -> String {
        let m = Int((hours * 60).rounded())
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) m"
    }

    private func debtLine(_ t: SleepVisuals.Tonight) -> String {
        let source = t.fromSchedule ? "Planned around your alarm." : "Planned around your usual wake time. Set a wake-up in Settings to lock it in."
        if t.debtHours >= 0.5 {
            return String(format: "You're %.1f h short this week, so tonight adds %d min to pay some back. ", t.debtHours, t.extraMinutes) + source
        }
        return "No sleep debt this week. Same window keeps it that way. " + source
    }

    /// Minutes past midnight → "10:45 PM".
    private func clock(_ minutes: Int) -> String {
        let date = calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: Date())) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
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
                hypnogram(night)
                    .frame(height: 170)
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
                Text("Only stage totals for this night — the full-night graph appears once your watch's stage timeline syncs.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
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

    private func stageName(_ stage: HealthKitManager.SleepStage) -> String {
        stage == .rem ? "REM" : stage.rawValue.capitalized
    }

    /// The whole night, bedtime to wake-up, one row per stage. Drag across
    /// it to read the stage at any minute.
    private func hypnogram(_ night: HealthInsights.Night) -> some View {
        let segments = model.hypnogram
        let start = min(night.bedtime, segments.first?.start ?? night.bedtime)
        let end = max(night.wakeTime, segments.map(\.end).max() ?? night.wakeTime)
        let hours = end.timeIntervalSince(start) / 3600
        let order: [HealthKitManager.SleepStage] = [.awake, .rem, .light, .deep]
        let scrubbed = scrubbedTime.flatMap { t in segments.first { $0.start <= t && t < $0.end } }
        return VStack(spacing: 6) {
            Chart {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    RectangleMark(
                        xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                        y: .value("Stage", stageName(seg.stage)),
                        height: .ratio(0.8)
                    )
                    .foregroundStyle(stageColor(seg.stage).opacity(scrubbed == nil || scrubbed == seg ? 1 : 0.45))
                    .cornerRadius(2)
                }
                if let t = scrubbedTime, let seg = scrubbed {
                    RuleMark(x: .value("Time", t))
                        .foregroundStyle(Neka.ink.opacity(0.35))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            chartBubble("\(t.formatted(date: .omitted, time: .shortened)) · \(stageName(seg.stage)) \(duration(Int(seg.end.timeIntervalSince(seg.start) / 60)))")
                        }
                }
            }
            .chartXSelection(value: $scrubbedTime)
            .chartXScale(domain: start...end)
            .chartYScale(domain: order.map(stageName))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: hours > 9 ? 3 : 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.system(size: 11, weight: .medium))
                }
            }
            HStack {
                Label(night.bedtime.formatted(date: .omitted, time: .shortened), systemImage: "bed.double.fill")
                Spacer()
                Label(night.wakeTime.formatted(date: .omitted, time: .shortened), systemImage: "sun.max.fill")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Neka.inkSecondary)
        }
    }

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: - Timeline

    private func timelineCard(_ night: HealthInsights.Night) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthCardHeader(title: "Sleep Timeline",
                             trailing: night.periods.count > 1 ? "split into \(night.periods.count) sessions" : nil)
            nightStrip(night)
                .frame(height: 16)
            HStack {
                Text(night.bedtime.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(night.wakeTime.formatted(date: .omitted, time: .shortened))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Neka.inkSecondary)
            .padding(.top, -6)
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

    /// Bedtime → wake-up drawn to scale: stage colors when known, otherwise
    /// the stretches you were asleep, with any time up in between left as
    /// a gap.
    private func nightStrip(_ night: HealthInsights.Night) -> some View {
        let start = night.bedtime
        let total = max(60, night.wakeTime.timeIntervalSince(start))
        let staged = model.hypnogram.filter { $0.end > start && $0.start < night.wakeTime }
        return GeometryReader { geo in
            let w = geo.size.width
            let x = { (d: Date) -> CGFloat in w * CGFloat(max(0, min(total, d.timeIntervalSince(start))) / total) }
            ZStack(alignment: .leading) {
                Rectangle().fill(Neka.track)
                if staged.isEmpty {
                    ForEach(night.periods, id: \.start) { p in
                        Rectangle()
                            .fill(LinearGradient(colors: [Neka.lavender, deepBlue], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(2, x(p.end) - x(p.start)))
                            .offset(x: x(p.start))
                    }
                } else {
                    ForEach(Array(staged.enumerated()), id: \.offset) { _, seg in
                        Rectangle()
                            .fill(stageColor(seg.stage))
                            .frame(width: max(1, x(seg.end) - x(seg.start)))
                            .offset(x: x(seg.start))
                    }
                }
            }
            .clipShape(Capsule())
        }
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
            }
        }
        .frame(minWidth: 96, alignment: .leading)
    }
}
