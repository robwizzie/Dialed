//
//  HealthView.swift
//  Dialed
//
//  The Health tab: a deep look at Body, Sleep and Nutrition for any of the
//  last 14 days. Same Neka look as Home — big title, date stepper, pill
//  tabs, then cards you can tap into. Charts are touch-scrubbable.
//

import SwiftUI
import SwiftData
import Charts

struct HealthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = HealthDetailModel()
    @State private var showClassicTrends = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    sectionPicker
                    Group {
                        switch router.healthSection {
                        case .body:      HealthBodyPage(model: model)
                        case .sleep:     HealthSleepPage(model: model)
                        case .nutrition: HealthNutritionPage(model: model)
                        }
                    }
                    .nekaLoading(model.isShowingStaleDay)
                    .transition(.opacity)

                    Button { showClassicTrends = true } label: {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text("Pillar trends")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(16)
                        .nekaCard()
                    }
                    .buttonStyle(.dialedScale)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.2), value: router.healthSection)
            }
            .refreshable {
                await syncWatch()
                await model.load(context: modelContext)
            }
            .nekaSceneBackground(scene)
            .nekaStatusBarScrim(scene.top)
            .animation(.easeInOut(duration: 0.35), value: router.healthSection)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: model.day) { await model.load(context: modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
            Task { await model.load(context: modelContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchDataDidSync)) { _ in
            Task { await model.load(context: modelContext) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.rollToToday() }
        }
        .sheet(isPresented: $showClassicTrends) {
            PillarTrendsView()
                .environment(\.colorScheme, .dark)
                .presentationDragIndicator(.visible)
        }
    }

    /// Pull to refresh asks Google Health for the last two nights, so a
    /// Pixel Watch night that landed after Home's last sync shows up here.
    private func syncWatch() async {
        guard GoogleHealthSyncService.isConnected else { return }
        let sync = GoogleHealthSyncService(modelContext: modelContext)
        await sync.sync(days: 2)
        DataDiagnostics.shared.watchError = sync.lastError
        if sync.lastError == nil {
            UserDefaults.standard.set(Date(), forKey: "home.lastGoogleHealthSync")
        }
    }

    // MARK: - Header

    private var scene: Neka.Scene { router.healthSection.scene }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(router.healthSection.title)
                    .font(Neka.display(34, weight: .medium))
                    .foregroundColor(scene.ink)
                Spacer()
                dayStepper
            }
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(scene.inkSecondary)
        }
        .padding(.top, 12)
    }

    private var subtitle: String {
        switch router.healthSection {
        case .body:      return "Track your physical health and performance."
        case .sleep:     return "Understand and improve your rest."
        case .nutrition: return "Fuel your body with intention."
        }
    }

    private var dayStepper: some View {
        HStack(spacing: 6) {
            stepButton("chevron.left", enabled: model.canGoBack) { model.shift(-1) }
            Text(model.isToday ? "Today" : model.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(scene.inkSecondary)
                .frame(minWidth: 64)
                .contentTransition(.numericText())
            stepButton("chevron.right", enabled: model.canGoForward) { model.shift(1) }
        }
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(scene.ink.opacity(enabled ? 1 : 0.35))
                .frame(width: 34, height: 34)
                .background(Circle().fill(scene.glass))
                .overlay(Circle().stroke(scene.glassStroke, lineWidth: 1))
        }
        .disabled(!enabled)
        .accessibilityLabel(icon == "chevron.left" ? "Previous day" : "Next day")
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(HealthSection.allCases) { section in
                let selected = section == router.healthSection
                Button {
                    router.healthSection = section
                } label: {
                    Label(section.title, systemImage: section.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selected ? scene.onInk : scene.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(selected ? scene.ink : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(scene.glass))
        .overlay(Capsule().stroke(scene.glassStroke, lineWidth: 1))
    }
}

extension HealthSection {
    /// Each page's color mood: lime body, violet night, icy fuel and water.
    var scene: Neka.Scene {
        switch self {
        case .body:      return .lime
        case .sleep:     return .violet
        case .nutrition: return .ice
        }
    }
}

// MARK: - Shared components

/// Small "↑ 12%" chip. `goodWhenUp` flips the color for metrics like
/// resting heart rate where lower is better.
struct HealthDeltaChip: View {
    let percent: Double
    var goodWhenUp = true

    var body: some View {
        let up = percent >= 0
        let good = up == goodWhenUp
        HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up" : "arrow.down")
            Text("\(Int(abs(percent).rounded()))%")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(abs(percent) < 1 ? Neka.inkSecondary : (good ? Neka.greenText : Neka.roseText))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(abs(percent) < 1 ? Neka.track : (good ? Neka.greenSoft : Neka.roseSoft)))
    }
}

/// Title row used by every Health card.
struct HealthCardHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
    }
}

/// The 0–100 gradient bar with a dot at the score.
struct HealthScoreBar: View {
    let score: Int

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track)
                    Capsule()
                        .fill(LinearGradient(colors: [Neka.sky.opacity(0.6), Neka.lavender, Neka.green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, score))) / 100)
                    Circle()
                        .fill(Neka.green)
                        .overlay(Circle().stroke(Neka.surface, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: geo.size.width * CGFloat(min(100, max(0, score))) / 100 - 8)
                }
            }
            .frame(height: 10)
            HStack {
                ForEach([0, 25, 50, 75, 100], id: \.self) { t in
                    Text("\(t)")
                    if t != 100 { Spacer() }
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Neka.inkSecondary)
        }
    }
}

/// Insight rows with a tinted round icon.
struct HealthInsightsCard: View {
    let title: String
    let insights: [HealthInsights.Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthCardHeader(title: title)
            if insights.isEmpty {
                Text("Nothing stands out today. More nights and meals logged = sharper insights.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
            ForEach(insights) { insight in
                HStack(spacing: 12) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint(insight.tone))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(tint(insight.tone).opacity(0.15)))
                    Text(insight.text)
                        .font(.system(size: 13))
                        .foregroundColor(Neka.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func tint(_ tone: HealthInsights.Insight.Tone) -> Color {
        switch tone {
        case .good:    return Neka.green
        case .neutral: return Neka.sky
        case .watch:   return Neka.orange
        }
    }
}

/// A two-column grid of metric tiles.
struct HealthTileGrid<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            content
        }
    }
}

/// One metric tile: title, big number, a chip, a small chart, a footer.
struct HealthTile<ChartContent: View>: View {
    let title: String
    let value: String
    let unit: String
    var delta: Double? = nil
    var goodWhenUp = true
    var status: String? = nil
    var statusColor: Color = Neka.greenText
    var footnote: String? = nil
    var wash: Neka.Wash = .plain
    @ViewBuilder let chart: ChartContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.ink)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }
            if let delta {
                HealthDeltaChip(percent: delta, goodWhenUp: goodWhenUp)
            }
            chart
                .frame(height: 44)
                .frame(maxWidth: .infinity)
            HStack {
                if let status {
                    Text(status)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard(wash: wash)
        .accessibilityElement(children: .combine)
    }
}

/// Tiny line chart for tiles and metric rows.
struct HealthSparkline: View {
    let values: [HealthInsights.DayValue]
    var tint: Color = Neka.green

    var body: some View {
        if values.count >= 2 {
            Chart(values, id: \.date) { v in
                LineMark(x: .value("Day", v.date), y: .value("Value", v.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                AreaMark(x: .value("Day", v.date), y: .value("Value", v.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        } else {
            Text("Not enough data yet")
                .font(.system(size: 10))
                .foregroundColor(Neka.inkTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Tiny bar chart; the last bar is highlighted.
struct HealthMiniBars: View {
    let values: [Double]
    var tint: Color = Neka.sky
    var target: Double? = nil

    var body: some View {
        if values.contains(where: { $0 > 0 }) {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    BarMark(x: .value("i", i), y: .value("v", v), width: .ratio(0.6))
                        .foregroundStyle(i == values.count - 1 ? tint : tint.opacity(0.35))
                        .cornerRadius(3)
                }
                if let target {
                    RuleMark(y: .value("Target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Neka.inkTertiary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        } else {
            Text("No data yet")
                .font(.system(size: 10))
                .foregroundColor(Neka.inkTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// "6 AM"-style hour label for chart axes.
func healthHourLabel(_ hour: Int) -> String {
    let midnight = Calendar.current.startOfDay(for: Date())
    let date = Calendar.current.date(byAdding: .hour, value: hour, to: midnight) ?? midnight
    return date.formatted(.dateTime.hour())
}
