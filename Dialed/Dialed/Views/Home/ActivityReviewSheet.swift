//
//  ActivityReviewSheet.swift
//  Dialed
//
//  A closer look at a heart-rate stretch before you name it: the heart
//  rate from 15 minutes before to 15 after (the stretch shaded, with your
//  resting and "active" lines), time in each effort zone, and what else
//  says you were moving — steps, active calories, distance, flights and
//  any workout that overlaps. Name it, or say it wasn't anything.
//

import SwiftUI
import SwiftData
import Charts

struct ActivityReviewSheet: View {
    let bout: ActiveBouts.Bout
    /// After it's named or dismissed (refresh whatever showed it).
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var evidence: ActivityWindowService.Evidence?
    @State private var naming: HomeFunCard.NamingTarget?

    private var resting: Double { ActivityReview.resting(average: bout.averageBPM, effort: bout.effort) }
    private var activeLine: Double { ActivityReview.activeLine(resting: resting) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    chartCard
                    zonesCard
                    evidenceCard
                    actions
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .nekaPageBackground()
            .navigationTitle("Review activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { evidence = await ActivityWindowService.load(bout, context: context) }
            .sheet(item: $naming) { target in
                FunActivitySheet(target: target) {
                    RecentSuggestions.invalidate()
                    onDone()
                    dismiss()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HomeFunCard.timeRange(bout.start, bout.end) + " · " + bout.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            HStack(spacing: 10) {
                stat("\(Int(bout.minutes.rounded()))", "min")
                stat("\(Int(bout.averageBPM))", "avg bpm")
                stat("\(Int(bout.peakBPM))", "peak")
                stat("~\(Int(bout.calories))", "cal")
            }
            Text("\(bout.intensity) effort, about \(Int((bout.effort * 100).rounded()))% of your heart-rate reserve.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .nekaCard(wash: .peach)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Neka.display(22, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Neka.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Neka.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Heart rate

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Heart rate")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                if let sources = evidence?.heartSources, !sources.isEmpty {
                    Text(sources.joined(separator: " + "))
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            if let e = evidence {
                if e.heartRate.isEmpty {
                    Text("No heart-rate readings came back for this window.")
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    heartChart(e)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            }
            HStack(spacing: 14) {
                legend(Neka.rose.opacity(0.18), "This stretch")
                legend(Neka.orange, "Active \(Int(activeLine)) bpm")
                legend(Neka.inkTertiary, "Resting ~\(Int(resting))")
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func heartChart(_ e: ActivityWindowService.Evidence) -> some View {
        let values = e.heartRate.map(\.bpm)
        let low = min(resting, values.min() ?? resting) - 5
        let high = max(activeLine, values.max() ?? activeLine) + 5
        return Chart {
            RectangleMark(xStart: .value("Start", bout.start), xEnd: .value("End", bout.end),
                          yStart: .value("Low", low), yEnd: .value("High", high))
                .foregroundStyle(Neka.rose.opacity(0.12))
            RuleMark(y: .value("Active", activeLine))
                .foregroundStyle(Neka.orange)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            RuleMark(y: .value("Resting", resting))
                .foregroundStyle(Neka.inkTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            ForEach(Array(e.heartRate.enumerated()), id: \.offset) { _, s in
                LineMark(x: .value("Time", s.date), y: .value("bpm", s.bpm))
                    .foregroundStyle(Neka.rose)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: low...high)
        .chartXScale(domain: e.start...e.end)
        .frame(height: 200)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 6)
            Text(text).font(.system(size: 10)).foregroundColor(Neka.inkSecondary)
        }
    }

    // MARK: - Zones

    private var zonesCard: some View {
        let zones = evidence.map { ActivityReview.zones($0.heartRate, from: bout.start, to: bout.end, resting: resting) } ?? []
        let total = max(1, zones.reduce(0) { $0 + $1.minutes })
        let colors: [Color] = [Neka.sky, Neka.green, Neka.orange, Neka.rose]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Effort")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            if zones.isEmpty || zones.allSatisfy({ $0.minutes == 0 }) {
                Text(evidence == nil ? "Reading your heart rate…" : "Not enough readings to split by effort.")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                            if z.minutes > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colors[i % colors.count])
                                    .frame(width: max(4, geo.size.width * z.minutes / total))
                            }
                        }
                    }
                }
                .frame(height: 12)
                HStack {
                    ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle().fill(colors[i % colors.count]).frame(width: 7, height: 7)
                                Text(z.name).font(.system(size: 11, weight: .semibold)).foregroundColor(Neka.ink)
                            }
                            Text("\(Int(z.minutes.rounded())) min")
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundColor(Neka.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Other evidence

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What else says you were moving")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            if let e = evidence {
                evidenceRow("figure.walk", "Steps", e.steps.map { "\(Int($0).formatted())" })
                evidenceRow("flame.fill", "Active calories (watch)", e.activeCalories.map { "\(Int($0)) cal" })
                evidenceRow("point.topleft.down.to.point.bottomright.curvepath", "Distance", e.miles.map { String(format: "%.2f mi", $0) })
                evidenceRow("figure.stairs", "Flights climbed", e.flights.map { "\(Int($0))" })
                if e.workouts.isEmpty {
                    evidenceRow("applewatch", "Recorded workout", nil)
                } else {
                    ForEach(e.workouts) { w in
                        evidenceRow("applewatch", "Workout · \(w.source)", "\(w.title) \(w.timeText)")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func evidenceRow(_ icon: String, _ title: String, _ value: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(value == nil ? Neka.inkTertiary : Neka.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Neka.track))
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Neka.ink)
            Spacer()
            Text(value ?? "None")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(value == nil ? Neka.inkTertiary : Neka.ink)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button { naming = .bout(bout) } label: {
                Text("Name it")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Neka.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Neka.ink))
            }
            .buttonStyle(.dialedScale)
            Button {
                FunActivityService.dismiss(bout)
                RecentSuggestions.invalidate()
                onDone()
                dismiss()
            } label: {
                Text("Not an activity")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }
}
