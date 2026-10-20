//
//  StrengthProgressView.swift
//  Dialed
//
//  Strength vs weight: for each main lift, the best estimated 1RM
//  (Epley) of every logged session, next to the body-weight trend over
//  the same weeks. The point of a cut is to lose fat while keeping (or
//  growing) strength — this is the screen that shows it.
//

import SwiftUI
import SwiftData
import Charts

struct StrengthProgressView: View {
    @Environment(\.modelContext) private var context

    typealias Lift = StrengthProgression.MainLift
    typealias Point = StrengthProgression.SessionPoint

    @State private var lift: Lift = .bench
    @State private var series: [Lift: [Point]] = [:]
    @State private var weights: [WeightChallengeEngine.DailyWeight] = []
    @State private var loading = true
    /// Every weighted exercise's best estimated max, strongest first.
    @State private var bests: [StrengthMilestones.Best] = []

    private var points: [Point] { series[lift] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headlineCard
                liftGrid
                liftChartCard
                if !bests.isEmpty { milestonesCard }
                weightChartCard
                Text("e1RM = estimated one-rep max (Epley: weight × (1 + reps ÷ 30)), from the best finished set of each session. Log workouts from the plan to fill this in.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Strength vs weight")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
            Task { await load() }
        }
    }

    // MARK: - Data

    private func load() async {
        let sets = PlanWorkoutLogStore.allSets(context: context)
        var next: [Lift: [Point]] = [:]
        for l in Lift.allCases {
            let mine = sets.filter { l.matches($0.exerciseName) }
            let grouped = Dictionary(grouping: mine, by: \.workoutID)
            let sessions = grouped.values.compactMap { rows -> (date: Date, sets: [StrengthProgression.LoggedSet])? in
                guard let first = rows.first else { return nil }
                return (date: first.date, sets: rows.map(\.asLoggedSet))
            }
            next[l] = StrengthProgression.e1RMSeries(sessions)
        }
        series = next
        bests = StrengthMilestones.bests(sets.filter(\.completed).map {
            StrengthMilestones.SetRecord(exercise: $0.exerciseName, date: $0.date, weight: $0.weightLbs, reps: $0.reps)
        }).values.sorted { $0.e1RM > $1.e1RM }

        let earliest = sets.first?.date ?? Date()
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let since = Calendar.current.date(byAdding: .day, value: -7, to: min(earliest, sixtyDaysAgo)) ?? sixtyDaysAgo
        let readings = await WeightDataSource.readings(context: context, since: since)
        weights = WeightChallengeEngine.dailySeries(readings)
        loading = false

        // Open on the lift with the most history.
        if (series[lift] ?? []).isEmpty,
           let best = Lift.allCases.max(by: { (series[$0]?.count ?? 0) < (series[$1]?.count ?? 0) }),
           (series[best]?.count ?? 0) > 0 {
            lift = best
        }
    }

    /// Trend weight on (or just before) `date`; the first reading if none before.
    private func trendWeight(at date: Date) -> Double? {
        let day = Calendar.current.startOfDay(for: date)
        return weights.last(where: { $0.day <= day })?.trend ?? weights.first?.trend
    }

    private var weightWindow: [WeightChallengeEngine.DailyWeight] {
        guard let first = points.first?.date,
              let from = Calendar.current.date(byAdding: .day, value: -7, to: first) else {
            let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
            return weights.filter { $0.day >= cutoff }
        }
        return weights.filter { $0.day >= Calendar.current.startOfDay(for: from) }
    }

    // MARK: - Headline

    private var headline: String {
        guard let first = points.first, let last = points.last else {
            return loading ? "Loading…" : "No \(lift.title.lowercased()) sessions logged yet"
        }
        if points.count == 1 {
            return "\(lift.title) e1RM \(formatPounds(last.e1RM.rounded())) lb — log another session to see the trend"
        }
        var weightChange: Double?
        if let a = trendWeight(at: first.date), let b = trendWeight(at: last.date) { weightChange = b - a }
        return StrengthProgression.headline(lift: lift.title, e1RMChange: last.e1RM - first.e1RM, weightChange: weightChange)
    }

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            NekaPill(text: "STRENGTH VS WEIGHT", tint: Neka.sky, fill: Neka.skySoft)
            Text(headline)
                .font(Neka.display(24, weight: .bold))
                .foregroundColor(Neka.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let first = points.first, let last = points.last, points.count > 1 {
                Text("\(points.count) sessions since \(first.date.formatted(.dateTime.month(.abbreviated).day())) · best \(formatPounds(points.map(\.e1RM).max()?.rounded() ?? last.e1RM)) lb")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            } else {
                Text("Keeping strength while the scale drops means you're losing fat, not muscle.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard(wash: .sky)
    }

    // MARK: - Estimated max & next milestones

    private var milestonesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Estimated max & next milestones")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
                .padding(.bottom, 6)
            ForEach(Array(bests.prefix(8).enumerated()), id: \.element.exercise) { i, best in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(best.exercise)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text("Best \(formatPounds(best.heaviest.weight)) × \(best.heaviest.reps)")
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkSecondary)
                        if let next = StrengthMilestones.nextMilestone(for: best) {
                            Label(next.text, systemImage: next.withinReach ? "flame.fill" : "flag.checkered")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(next.withinReach ? Neka.orangeText : Neka.greenText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatPounds(best.e1RM.rounded()))
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(Neka.ink)
                        Text("est. max")
                            .font(.system(size: 10))
                            .foregroundColor(Neka.inkTertiary)
                    }
                }
                .padding(.vertical, 8)
                if i < min(bests.count, 8) - 1 { Divider().overlay(Neka.hairline) }
            }
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Lift picker

    private var liftGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Lift.allCases) { l in
                let pts = series[l] ?? []
                let isSelected = l == lift
                Button { withAnimation(.easeInOut(duration: 0.2)) { lift = l } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isSelected ? Neka.onInk.opacity(0.8) : Neka.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(pts.last.map { formatPounds($0.e1RM.rounded()) } ?? "—")
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(isSelected ? Neka.onInk : Neka.ink)
                        Text(changeText(pts))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isSelected ? Neka.onInk.opacity(0.8) : changeColor(pts))
                            .lineLimit(1)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Neka.ink : Neka.surface)
                    )
                }
                .buttonStyle(.dialedScale)
            }
        }
    }

    private func changeText(_ pts: [Point]) -> String {
        guard let a = pts.first, let b = pts.last, pts.count > 1 else {
            return pts.isEmpty ? "no data" : "1 session"
        }
        return "\(StrengthProgression.signed(b.e1RM - a.e1RM)) lb"
    }

    private func changeColor(_ pts: [Point]) -> Color {
        guard let a = pts.first, let b = pts.last, pts.count > 1 else { return Neka.inkTertiary }
        return b.e1RM >= a.e1RM ? Neka.green : Neka.orange
    }

    // MARK: - Charts

    private var liftChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(lift.title) · estimated 1RM")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            if points.isEmpty {
                emptyChart("Log a session with \(lift.title.lowercased()) to start the chart.")
            } else {
                let values = points.map(\.e1RM)
                let lo = (values.min() ?? 0) - 10
                let hi = (values.max() ?? 0) + 10
                Chart {
                    ForEach(points, id: \.date) { p in
                        LineMark(x: .value("Date", p.date), y: .value("e1RM", p.e1RM))
                            .foregroundStyle(Neka.sky)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value("e1RM", p.e1RM))
                            .foregroundStyle(Neka.sky)
                            .symbolSize(40)
                    }
                }
                .chartYScale(domain: max(0, lo)...hi)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 190)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private var weightChartCard: some View {
        let window = weightWindow
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Body weight · trend")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                if let a = window.first, let b = window.last, window.count > 1 {
                    NekaPill(text: "\(StrengthProgression.signed(b.trend - a.trend)) lb",
                             tint: b.trend <= a.trend ? Neka.green : Neka.orange,
                             fill: b.trend <= a.trend ? Neka.greenSoft : Neka.orangeSoft)
                }
            }
            if window.count < 2 {
                emptyChart("Weigh in a few mornings to see your trend here.")
            } else {
                let values = window.map(\.pounds) + window.map(\.trend)
                let lo = (values.min() ?? 0) - 2
                let hi = (values.max() ?? 0) + 2
                Chart {
                    ForEach(window) { d in
                        PointMark(x: .value("Day", d.day), y: .value("Scale", d.pounds))
                            .foregroundStyle(Neka.inkTertiary.opacity(0.6))
                            .symbolSize(14)
                        LineMark(x: .value("Day", d.day), y: .value("Trend", d.trend))
                            .foregroundStyle(Neka.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(points, id: \.date) { p in
                        RuleMark(x: .value("Session", p.date))
                            .foregroundStyle(Neka.sky.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 170)
                Text("Green line is your smoothed trend; dots are daily weigh-ins; blue rules mark \(lift.title.lowercased()) sessions.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func emptyChart(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Neka.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .multilineTextAlignment(.center)
    }
}
