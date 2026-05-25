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
                    VStack(spacing: 20) {
                        windowSelector
                        pillarSelector
                        summaryCard
                        chartCard
                        breakdownCard
                        legacyLink
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .padding(.bottom, 32)
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

    private var windowSelector: some View {
        Picker("Window", selection: $viewModel.window) {
            ForEach(PillarTrendsViewModel.Window.allCases) { window in
                Text(window.rawValue).tag(window)
            }
        }
        .pickerStyle(.segmented)
    }

    private var pillarSelector: some View {
        HStack(spacing: 8) {
            ForEach(PillarTrendsViewModel.Pillar.allCases) { pillar in
                pillarChip(pillar)
            }
        }
    }

    private func pillarChip(_ pillar: PillarTrendsViewModel.Pillar) -> some View {
        let isSelected = viewModel.selectedPillar == pillar
        let gradient = gradient(for: pillar)
        return Button {
            viewModel.selectedPillar = pillar
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            Text(pillar.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected
                              ? AnyShapeStyle(LinearGradient(
                                  colors: gradient.map { $0.opacity(0.4) },
                                  startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected
                                        ? (gradient.last ?? .white).opacity(0.55)
                                        : Color.white.opacity(0.06),
                                        lineWidth: isSelected ? 1 : 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let summary = viewModel.summary(for: viewModel.selectedPillar)
        let gradient = gradient(for: viewModel.selectedPillar)
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.selectedPillar.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                trendArrow(slope: summary.trendPerDay)
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(summary.average.map(String.init) ?? "—")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                    )
                Text("avg")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 24) {
                statColumn(title: "Min", value: summary.min)
                Divider().frame(height: 28).background(.white.opacity(0.1))
                statColumn(title: "Max", value: summary.max)
                Divider().frame(height: 28).background(.white.opacity(0.1))
                statColumn(title: "Trend", value: summary.trendPerDay.map { Int($0.rounded()) }, suffix: " pts/d")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.nowCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColors.glassStroke, lineWidth: 0.5)
                )
        )
    }

    private func statColumn(title: String, value: Int?, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
            Text(value.map { "\($0)\(suffix)" } ?? "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendArrow(slope: Double?) -> some View {
        let icon: String
        let color: Color
        let label: String
        switch slope {
        case let s? where s > 0.3:
            icon = "arrow.up.right"; color = .green; label = "Up"
        case let s? where s < -0.3:
            icon = "arrow.down.right"; color = .red.opacity(0.85); label = "Down"
        case _?:
            icon = "arrow.right"; color = .white.opacity(0.5); label = "Flat"
        case nil:
            icon = "minus"; color = .white.opacity(0.3); label = "—"
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    // MARK: - Chart

    private var chartCard: some View {
        let points = viewModel.series[viewModel.selectedPillar] ?? []
        let gradient = gradient(for: viewModel.selectedPillar)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Daily score")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

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
                                (gradient.last ?? .white).opacity(0.25),
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
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: viewModel.window.days > 14 ? 7 : 2)) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.04))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .frame(height: 200)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.nowCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColors.glassStroke, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Breakdown list (each day)

    private var breakdownCard: some View {
        let points = (viewModel.series[viewModel.selectedPillar] ?? []).reversed()
        return VStack(alignment: .leading, spacing: 10) {
            Text("By day")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            VStack(spacing: 8) {
                ForEach(Array(points), id: \.id) { point in
                    dailyRow(point: point)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.nowCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColors.glassStroke, lineWidth: 0.5)
                )
        )
    }

    private func dailyRow(point: PillarTrendsViewModel.DailyPoint) -> some View {
        let gradient = gradient(for: viewModel.selectedPillar)
        return HStack {
            Text(dateLabel(point.date))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 90, alignment: .leading)

            if let score = point.score {
                GeometryReader { proxy in
                    let pct = max(0.02, min(1, Double(score) / 100.0))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.06))
                        Capsule()
                            .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * pct)
                    }
                }
                .frame(height: 8)

                Text("\(score)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 36, alignment: .trailing)
            } else {
                Capsule()
                    .fill(.white.opacity(0.04))
                    .frame(height: 8)
                Text("—")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 36, alignment: .trailing)
            }
        }
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
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Legacy trends")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Workouts, personal bests, score history")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColors.glassStroke, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
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
