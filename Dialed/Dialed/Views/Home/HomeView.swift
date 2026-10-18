//
//  HomeView.swift
//  Dialed
//
//  The Home tab, rebuilt in the light Neka style:
//
//    1. "Hello, <name>." greeting, date, devices + avatar
//    2. Hero — your photo with vitals pinned to your body
//    3. Weight-loss challenge scoreboard
//    4. Body state (Recovery / Readiness / Energy / Strain)
//    5. Metric tiles — Weight, Water, HRV, Sleep, Resting HR, Activity
//    6. Fuel — protein + calorie budget
//    7. Today's timeline
//    8. Coach — ranked nudges for today
//    9. Links into the deeper (legacy) screens
//    + floating quick-log bar: water, weigh-in, meal, voice
//
//  Phone-first: one column, 16pt gutters, 2-up tiles.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var stateModel = NowViewModel()
    @ObservedObject private var photos = ProfilePhotoStore.shared

    /// Switches the tab bar to the Challenge tab.
    var onOpenChallenge: () -> Void = {}

    @State private var sheet: HomeSheet?

    enum HomeSheet: String, Identifiable {
        case water, meal, weighIn, voice, profile, challengeSetup
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                        .padding(.top, 8)
                    hero
                    HomeChallengeCard(
                        challenge: viewModel.challenge,
                        progress: viewModel.progress,
                        onSetUp: { sheet = .challengeSetup }
                    )
                    .onTapGesture {
                        if viewModel.challenge != nil { onOpenChallenge() }
                    }
                    HomeStateStrip(items: stateItems)
                    tiles
                    HomeFuelCard(
                        protein: viewModel.proteinGrams,
                        proteinTarget: viewModel.proteinTarget,
                        calories: viewModel.caloriesIn,
                        calorieTarget: viewModel.calorieTarget,
                        onLogMeal: { sheet = .meal }
                    )
                    HomeTimelineCard(items: viewModel.timeline)
                    HomeCoachCard(insights: viewModel.insights)
                    moreLinks
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .nekaPageBackground()
            .overlay(alignment: .bottom) { quickLogBar }
            .toolbar(.hidden, for: .navigationBar)
            .task { await refreshAll() }
            .refreshable { await refreshAll() }
            .onReceive(NotificationCenter.default.publisher(for: WeightChallenge.didChangeNotification)) { _ in
                Task { await refreshAll() }
            }
            .sheet(item: $sheet, onDismiss: { Task { await refreshAll() } }) { sheet in
                sheetContent(sheet)
            }
        }
        .environment(\.colorScheme, .light)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color.white.opacity(0.94), for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
    }

    private func refreshAll() async {
        await viewModel.refresh(context: modelContext)
        await stateModel.refresh(context: modelContext)
    }

    // MARK: - Header

    private var displayName: String {
        viewModel.firstName.trimmingCharacters(in: .whitespaces).ifEmpty("there")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.dateLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
                    .padding(.bottom, 10)
                Text("Hello,")
                    .font(Neka.display(30, weight: .light))
                    .foregroundColor(Neka.ink)
                Text("\(displayName).")
                    .font(Neka.display(42, weight: .bold))
                    .tracking(-1)
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Here's your health today.")
                    .font(.system(size: 15))
                    .foregroundColor(Neka.inkSecondary)
                    .padding(.top, 4)
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                NavigationLink {
                    DevicesView()
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.white.opacity(0.9)))
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
                }
                .accessibilityLabel("Devices")

                Button { sheet = .profile } label: { avatar }
                    .buttonStyle(.dialedScale)
                    .accessibilityLabel("Profile and photo")
            }
            .padding(.top, 2)
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = photos.original {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

            Circle()
                .fill(FitbitTokenStore.isConnected ? Neka.green : Neka.inkTertiary)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HomeHeroView(
            image: photos.heroImage,
            isCutout: photos.hasCutout,
            isProcessing: photos.isProcessing,
            photoScale: photos.heroScale,
            photoOffsetY: photos.heroOffsetY,
            heartRate: viewModel.heartRate,
            heartRateIsLive: viewModel.heartRateIsLive,
            breathingRate: viewModel.breathingRate,
            spO2: viewModel.spO2,
            weight: viewModel.latestWeight?.pounds,
            weightNote: weightNote,
            caption: heroCaption,
            onTapPhoto: { sheet = .profile }
        )
    }

    private var weightNote: String? {
        guard let latest = viewModel.latestWeight else { return nil }
        if Calendar.current.isDateInToday(latest.date) { return "Today" }
        return latest.date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var heroCaption: String {
        if let p = viewModel.progress, let c = viewModel.challenge {
            if p.daysLeft == 0 { return "Challenge complete.\nDown \(String(format: "%.1f", p.lostLbs)) lb." }
            return "Day \(p.dayNumber) vs. \(c.friendDisplayName).\nEvery choice counts today."
        }
        return "Real-time insights\nfor a healthier you."
    }

    // MARK: - Body state

    private var stateItems: [HomeStateStrip.Item] {
        [
            .init(name: "Recovery", score: stateModel.recovery.score, colors: [Neka.green, Color(hex: "9BE2AE")]),
            .init(name: "Readiness", score: stateModel.readiness.score, colors: [Neka.sky, Neka.blue]),
            .init(name: "Energy", score: stateModel.energy.score, colors: [Neka.amber, Neka.orange]),
            .init(name: "Strain", score: stateModel.strain.score, colors: [Neka.rose, Neka.lavender])
        ]
    }

    // MARK: - Tiles

    private var tiles: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            Button(action: onOpenChallenge) { weightTile }
                .buttonStyle(.dialedScale)
            Button { sheet = .water } label: { waterTile }
                .buttonStyle(.dialedScale)
            hrvTile
            sleepTile
            heartTile
            activityTile
        }
    }

    private var weightTile: some View {
        let trend = viewModel.progress?.series.suffix(30).map(\.trend)
            ?? WeightChallengeEngine.dailySeries(viewModel.weightReadings).suffix(30).map(\.trend)
        let lost = viewModel.progress?.lostLbs
        return HomeMetricTile(
            title: "Weight",
            value: viewModel.latestWeight.map { String(format: "%.1f", $0.pounds) } ?? "--",
            unit: "lb",
            wash: .mint,
            showsArrow: true,
            pill: lost.map { l in
                (text: l >= 0 ? "−\(String(format: "%.1f", l)) lb" : "+\(String(format: "%.1f", -l)) lb",
                 tint: l >= 0 ? Neka.green : Neka.rose,
                 fill: l >= 0 ? Color.white.opacity(0.85) : Neka.roseSoft)
            },
            footer: viewModel.progress?.startWeight.map { "Start \(String(format: "%.1f", $0))" } ?? "Connect your scale",
            footerTrailing: viewModel.progress.map { "Goal −\(String(format: "%.0f", $0.goalLossLbs))" }
        ) {
            NekaSparkline(values: Array(trend), color: Neka.green, fill: true)
                .frame(height: 38)
        }
    }

    private var waterTile: some View {
        let progress = viewModel.waterTargetOz > 0 ? viewModel.waterOz / viewModel.waterTargetOz : 0
        return HomeMetricTile(
            title: "Water",
            value: "\(Int(viewModel.waterOz))",
            unit: "oz",
            wash: .sky,
            showsArrow: true,
            footer: "of \(Int(viewModel.waterTargetOz)) oz",
            footerTrailing: "\(Int((min(progress, 9.99)) * 100))%"
        ) {
            HStack(alignment: .bottom, spacing: 10) {
                NekaBottle(progress: progress)
                    .frame(width: 26, height: 46)
                NekaBars(values: viewModel.waterWeek, color: Neka.sky, muted: Neka.sky.opacity(0.25), spacing: 3)
                    .frame(height: 34)
            }
            .frame(height: 46)
        }
    }

    private var hrvTile: some View {
        let status: String = {
            guard let hrv = viewModel.hrv, let base = viewModel.hrvBaseline, base > 0 else {
                return viewModel.hrv == nil ? "Wear your watch to sleep" : "Building baseline"
            }
            let delta = (hrv - base) / base
            if delta >= 0.05 { return "Optimal" }
            if delta <= -0.15 { return "Below baseline" }
            return "Normal"
        }()
        return HomeMetricTile(
            title: "HRV",
            value: viewModel.hrv.map { "\(Int($0.rounded()))" } ?? "--",
            unit: "ms",
            footer: status
        ) {
            NekaBars(values: Array(viewModel.hrvSeries.suffix(14)), color: Neka.lavender, muted: Neka.lavender.opacity(0.3), spacing: 3)
                .frame(height: 44)
        }
    }

    private var sleepTile: some View {
        let series = viewModel.sleepSeries
        let avg = series.dropLast().isEmpty ? nil : series.dropLast().reduce(0, +) / Double(series.count - 1)
        let deltaText: String? = {
            guard let last = viewModel.sleepHours, let avg, avg > 0 else { return nil }
            let pct = Int(((last - avg) / avg * 100).rounded())
            return pct >= 0 ? "+\(pct)%" : "\(pct)%"
        }()
        let quality: String = {
            guard let h = viewModel.sleepHours else { return "No sleep data" }
            if h >= 7 { return "Good" }
            if h >= 6 { return "Fair" }
            return "Short"
        }()
        return HomeMetricTile(
            title: "Sleep",
            value: viewModel.sleepHours.map { String(format: "%.1f", $0) } ?? "--",
            unit: "hours",
            footer: quality,
            footerTrailing: deltaText
        ) {
            NekaSparkline(values: series, color: Neka.blue, showsEndDot: false)
                .frame(height: 40)
        }
    }

    private var heartTile: some View {
        let rhr = viewModel.restingHR
        let status: String = {
            guard let rhr else { return "No data" }
            if rhr < 60 { return "Athletic" }
            if rhr <= 75 { return "Normal" }
            return "Elevated"
        }()
        return HomeMetricTile(
            title: "Resting HR",
            value: rhr.map { "\(Int($0.rounded()))" } ?? "--",
            unit: "bpm",
            wash: .rose,
            footer: status,
            footerTrailing: "40–100"
        ) {
            NekaHalfGauge(progress: rhr.map { ($0 - 40) / 60 } ?? 0.5)
                .frame(height: 46)
                .opacity(rhr == nil ? 0.4 : 1)
        }
    }

    private var activityTile: some View {
        let progress = Double(viewModel.steps) / Double(viewModel.stepGoal)
        return HomeMetricTile(
            title: "Activity",
            value: viewModel.steps.formatted(),
            unit: "steps"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                NekaBars(values: viewModel.stepsSeries.map(Double.init), color: Neka.ink, spacing: 4)
                    .frame(height: 28)
                Text("\(Int(min(progress, 9.99) * 100))% goal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                NekaProgressBar(progress: progress, tint: Neka.green, height: 6)
            }
        }
    }

    // MARK: - More

    private var moreLinks: some View {
        VStack(spacing: 0) {
            moreRow(icon: "clock.arrow.circlepath", title: "Day timeline", subtitle: "Everything you've logged today", tint: Neka.lavender, fill: Neka.lavenderSoft) {
                TimelineView()
            }
            Divider().overlay(Neka.hairline).padding(.leading, 62)
            moreRow(icon: "checklist", title: "Detailed tracking", subtitle: "Water, protein, routine checklist", tint: Neka.orange, fill: Neka.orangeSoft) {
                TodayView()
            }
            Divider().overlay(Neka.hairline).padding(.leading, 62)
            moreRow(icon: "calendar", title: "Score calendar", subtitle: "Streaks and past days", tint: Neka.green, fill: Neka.greenSoft) {
                CalendarView()
            }
        }
        .padding(.vertical, 4)
        .nekaCard()
    }

    private func moreRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        fill: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            // Legacy screens are designed dark.
            destination()
                .environment(\.colorScheme, .dark)
        } label: {
            HStack(spacing: 14) {
                NekaIconBadge(systemName: icon, tint: tint, fill: fill)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick log

    private var quickLogBar: some View {
        HStack(spacing: 6) {
            quickButton(icon: "drop.fill", label: "Water", tint: Neka.sky) { sheet = .water }
            quickButton(icon: "scalemass.fill", label: "Weigh in", tint: Neka.green) { sheet = .weighIn }
            quickButton(icon: "fork.knife", label: "Meal", tint: Neka.orange) { sheet = .meal }
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                sheet = .voice
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Neka.ink))
            }
            .buttonStyle(.dialedScale)
            .accessibilityLabel("Voice log")
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.6)))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
        )
        .padding(.bottom, 10)
    }

    private func quickButton(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Capsule().fill(Color.white.opacity(0.9)))
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("Log \(label.lowercased())")
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .water:
            WaterCaptureSheet()
                .environment(\.colorScheme, .dark)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        case .meal:
            MealCaptureSheet()
                .environment(\.colorScheme, .dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        case .voice:
            VoiceCaptureSheet()
                .environment(\.colorScheme, .dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        case .weighIn:
            WeighInSheet(lastWeight: viewModel.latestWeight?.pounds)
                .presentationDetents([.medium])
        case .profile:
            ProfileSheet()
                .presentationDetents([.large])
        case .challengeSetup:
            ChallengeSetupSheet(existing: nil, suggestedStartWeight: viewModel.latestWeight?.pounds)
                .presentationDetents([.large])
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: DialedSchema.allModels, inMemory: true)
}
