//
//  PillarTrendsView.swift
//  Dialed
//
//  New Trends tab content — four-pillar score history. Apple Charts
//  driven, pillar-segmented, with summary stats (avg / min / max / trend
//  arrow) and a NavigationLink down to the legacy TrendsView for the
//  detailed 1.x breakdowns until those features migrate.
//

import SwiftUI
import SwiftData
import Charts

struct PillarTrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = PillarTrendsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.nowBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        windowSelector
                        pillarSelector
                        summaryCard
                        chartCard
                        breakdownCard
                        legacyLink
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.load(context: modelContext) }
            .onChange(of: viewModel.window) { _, _ in
                viewModel.load(context: modelContext)
            }
            .refreshable { viewModel.load(context: modelContext) }
        }
    }

    // MARK: - Selectors

    /// Custom segmented control that matches the pillar chips visually
    /// so the two adjacent rows feel of-a-piece. The system .segmented
    /// Picker stuck out as generic against the bespoke chrome around it.
    private var windowSelector: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(PillarTrendsViewModel.Window.allCases) { window in
                windowChip(window)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                        .stroke(AppColors.glassStroke, lineWidth: 0.5)
                )
        )
    }

    private func windowChip(_ window: PillarTrendsViewModel.Window) -> some View {
        let isSelected = viewModel.window == window
        return Button {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                viewModel.window = window
            }
        } label: {
            Text(window.rawValue)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.sm, style: .continuous)
                        .fill(isSelected
                              ? AnyShapeStyle(LinearGradient(
                                  colors: AppColors.Pillar.readiness.gradient.map { $0.opacity(0.3) },
                                  startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.clear))
                )
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("Window \(window.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var pillarSelector: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(PillarTrendsViewModel.Pillar.allCases) { pillar in
                pillarChip(pillar)
            }
        }
    }

    private func pillarChip(_ pillar: PillarTrendsViewModel.Pillar) -> some View {
        let isSelected = viewModel.selectedPillar == pillar
        let gradient = gradient(for: pillar)
        return Button {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                viewModel.selectedPillar = pillar
            }
        } label: {
            Text(pillar.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.sm, style: .continuous)
                        .fill(isSelected
                              ? AnyShapeStyle(LinearGradient(
                                  colors: gradient.map { $0.opacity(0.4) },
                                  startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.sm, style: .continuous)
                                .stroke(isSelected
                                        ? (gradient.last ?? .white).opacity(0.55)
                                        : Color.white.opacity(0.06),
                                        lineWidth: isSelected ? 1 : 0.5)
                        )
                )
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel(pillar.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let summary = viewModel.summary(for: viewModel.selectedPillar)
        let gradient = gradient(for: viewModel.selectedPillar)
        return VStack(spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.selectedPillar.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                trendArrow(slope: summary.trendPerDay)
            }
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                if let avg = summary.average {
                    Text("\(avg)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                        )
                        .contentTransition(.numericText())
                } else {
                    // Don't render an em-dash through the pillar gradient —
                    // looks broken on empty state. Plain muted text instead.
                    Text("—")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.25))
                }
                Text("avg")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: summary.average)

            HStack(spacing: Spacing.lg) {
                statColumn(title: "Min", value: summary.min)
                statDivider
                statColumn(title: "Max", value: summary.max)
                statDivider
                statColumn(title: "Trend", value: summary.trendPerDay.map { Int($0.rounded()) }, suffix: " pts/d")
            }
        }
        .padding(Spacing.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dialedCard()
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedPillar)
    }

    /// Vertical hairline between stat columns. `Divider().frame(height:)`
    /// doesn't work reliably for vertical separators — use an explicit
    /// Rectangle.
    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 28)
    }

    private func statColumn(title: String, value: Int?, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
            Text(value.map { "\($0)\(suffix)" } ?? "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendArrow(slope: Double?) -> some View {
        let icon: String
        let color: Color
        let label: String
        switch slope {
        case let s? where s > 0.3:
            icon = "arrow.up.right"; color = AppColors.success; label = "Up"
        case let s? where s < -0.3:
            icon = "arrow.down.right"; color = AppColors.danger; label = "Down"
        case _?:
            icon = "arrow.right"; color = .white.opacity(0.55); label = "Flat"
        case nil:
            icon = "minus"; color = .white.opacity(0.35); label = "—"
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
        .accessibilityLabel("Trend \(label)")
    }

    // MARK: - Chart

    private var chartCard: some View {
        let points = viewModel.series[viewModel.selectedPillar] ?? []
        let gradient = gradient(for: viewModel.selectedPillar)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            DialedSectionHeader("Daily score")

            Chart(points) { point in
                if let score = point.score {
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Score", score)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                    )
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Score", score)
                    )
                    .foregroundStyle(gradient.last ?? .white)
                    .symbolSize(35)
                    AreaMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Score", score)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                (gradient.last ?? .white).opacity(0.28),
                                (gradient.first ?? .white).opacity(0.0)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: viewModel.window.days > 14 ? 7 : 2)) { _ in
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.04))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .frame(height: 200)
            .animation(.easeInOut(duration: 0.4), value: viewModel.selectedPillar)
            .animation(.easeInOut(duration: 0.4), value: viewModel.window)
            .accessibilityLabel("\(viewModel.selectedPillar.title) daily score chart, \(viewModel.window.rawValue) window")
        }
        .padding(Spacing.md + 2)
        .dialedCard()
    }

    // MARK: - Breakdown list (each day)

    private var breakdownCard: some View {
        let points = (viewModel.series[viewModel.selectedPillar] ?? []).reversed()
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            DialedSectionHeader("By day")
            VStack(spacing: Spacing.xs) {
                ForEach(Array(points), id: \.id) { point in
                    dailyRow(point: point)
                }
            }
        }
        .padding(Spacing.md + 2)
        .dialedCard()
    }

    /// One row per day. Uses an explicit `barWidth` GeometryReader bound
    /// to the row's available width (not the whole HStack) so the bar
    /// fills predictably without colliding with the label and value.
    private func dailyRow(point: PillarTrendsViewModel.DailyPoint) -> some View {
        let gradient = gradient(for: viewModel.selectedPillar)
        return HStack(spacing: Spacing.sm) {
            Text(dateLabel(point.date))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 90, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.06))
                    if let score = point.score {
                        let pct = max(0.02, min(1, Double(score) / 100.0))
                        Capsule()
                            .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * pct)
                    }
                }
            }
            .frame(height: 8)

            Text(point.score.map { "\($0)" } ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(point.score == nil ? .white.opacity(0.3) : .white)
                .frame(width: 36, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dateLabel(point.date)): \(point.score.map { String($0) } ?? "no data")")
    }

    private func dateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    // MARK: - Legacy bridge

    private var legacyLink: some View {
        NavigationLink {
            TrendsView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Legacy trends")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Workouts, personal bests, score history")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(Spacing.md)
            .dialedGlassCard()
        }
        .buttonStyle(.dialedScale)
        .accessibilityHint("Opens the legacy Trends view with workout history and personal bests")
    }

    // MARK: - Helpers

    private func gradient(for pillar: PillarTrendsViewModel.Pillar) -> [Color] {
        switch pillar {
        case .recovery:  return AppColors.Pillar.recovery.gradient
        case .readiness: return AppColors.Pillar.readiness.gradient
        case .energy:    return AppColors.Pillar.energy.gradient
        case .strain:    return AppColors.Pillar.strain.gradient
        }
    }
}

#Preview {
    PillarTrendsView()
        .preferredColorScheme(.dark)
}
