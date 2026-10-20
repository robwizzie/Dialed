//
//  HomeView.swift
//  Dialed
//
//  The Home tab, rebuilt in the light Neka style:
//
//    1. "Hello, <name>." greeting, date, devices + avatar
//    2. Hero — your photo with vitals pinned to your body
//    3. Weight-loss challenge scoreboard
//    4. Body state (Recovery / Readiness / Energy / Strain) + Body Check
//       (stress and illness watch)
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
    @StateObject private var briefModel = AIBriefModel()
    /// Overnight vitals for the Body Check card (stress + illness watch).
    @StateObject private var signals = HealthDetailModel()
    @ObservedObject private var studio = AvatarStudio.shared
    @AppStorage("avatar.useOnHome") private var useAvatarOnHome = true
    /// The morning card is hidden for the rest of this day once dismissed.
    @AppStorage("morning.dismissedDay") private var morningDismissedDay = ""
    @State private var aiAvailability: AIAvailability = DialedAI.availability
    @State private var askedForHealthAccess = false

    /// Switches the tab bar to the Challenge tab.
    var onOpenChallenge: () -> Void = {}

    @State private var sheet: HomeSheet?
    @State private var watchWorkouts: [DetectedWorkout] = []
    @State private var layout = HomeLayout.load()
    /// The day Home shows. Today is the live dashboard; a past day swaps the
    /// cards below the header for that day's recap, right here.
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    /// -1 stepping back, +1 forward: which way the content slides.
    @State private var dayDirection = -1

    private var showingToday: Bool { Calendar.current.isDateInToday(selectedDay) }
    @State private var path: [HomeDestination] = []
    @EnvironmentObject private var router: AppRouter

    /// 4 AM – noon, until you dismiss it.
    private var showsMorning: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return (4..<12).contains(hour) && morningDismissedDay != Self.dayKey(Date())
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    enum HomeSheet: String, Identifiable {
        case water, meal, eatingOut, weighIn, voice, profile, challengeSetup, ask, avatar, logWorkout, customize, pickDay
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        header
                            .padding(.top, 8)
                            .id("home-top")
                            .contentShape(Rectangle())
                            .simultaneousGesture(daySwipe)
                        dayContent
                            .id(DayLoadKit.key(selectedDay))
                            .transition(.asymmetric(
                                insertion: .move(edge: dayDirection < 0 ? .leading : .trailing).combined(with: .opacity),
                                removal: .move(edge: dayDirection < 0 ? .trailing : .leading).combined(with: .opacity)))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .onChange(of: selectedDay) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("home-top", anchor: .top) }
                }
            }
            .scrollIndicators(.hidden)
            .nekaPageBackground()
            .nekaStatusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await requestHealthAccessIfNeeded()
                await refreshAll()
            }
            .refreshable {
                if showingToday {
                    await refreshAll(force: true)
                } else {
                    await DayRecapStore.shared.load(selectedDay, context: modelContext, force: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: WeightChallenge.didChangeNotification)) { _ in
                Task { await refreshAll(force: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: MileSettings.didChange)) { _ in
                Task { await refreshAll(force: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: HomeLayout.didChange)) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { layout = HomeLayout.load() }
            }
            .onReceive(NotificationCenter.default.publisher(for: GoalEvent.didChangeNotification)) { _ in
                viewModel.refreshGoal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
                Task { await refreshAll(force: true) }
            }
            // Requests from the bottom bar's nested menu.
            .onChange(of: router.homeSheet) { _, request in
                guard let request else { return }
                sheet = request
                router.homeSheet = nil
            }
            .onChange(of: router.homePush) { _, request in
                guard let request else { return }
                path = [request]
                router.homePush = nil
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .workout:
                    WorkoutPlanView()
                case .weeklyReview:
                    WeeklyReviewView()
                case .timeline:
                    TimelineView().environment(\.colorScheme, .dark)
                case .foodLog:
                    FoodLogView()
                case .calendar:
                    CalendarView().environment(\.colorScheme, .dark)
                case .devices:
                    DevicesView()
                case .strength:
                    StrengthProgressView()
                case .progressPhotos:
                    ProgressPhotosView()
                case .mileHistory:
                    MileHistoryView()
                case .weightTrend:
                    TrendWeightView()
                case .mealPlan:
                    MealPlanView()
                case .schedule:
                    ScheduleView()
                case .pulse:
                    PulseCheckView()
                case .metabolism:
                    MetabolismView()
                case .wakeUp:
                    WakeScheduleView()
                case .calendars:
                    CalendarSettingsView()
                case .badges:
                    BadgesView()
                case .habits:
                    HabitHeatmapView()
                case .notifications:
                    NotificationsSettingsView()
                case .activity:
                    SuggestedActivityPage()
                }
            }
            .sheet(item: $sheet, onDismiss: { Task { await refreshAll(force: true) } }) { sheet in
                sheetContent(sheet)
            }
        }
    }

    private func refreshAll(force: Bool = false) async {
        // Skipped refreshes (tab re-appear within a minute) do nothing else.
        guard await viewModel.refresh(context: modelContext, force: force) else { return }
        await stateModel.refresh(context: modelContext)
        signals.day = Calendar.current.startOfDay(for: Date())
        await signals.loadSignals(context: modelContext)
        aiAvailability = DialedAI.availability
        await briefModel.refreshIfStale(viewModel.snapshot)
        // Once avatars are on, quietly fill in today's mood look.
        if let mood = viewModel.moodReading?.mood {
            await studio.ensure(mood: mood)
        }
        // Steps, sleep, score, challenge and today's avatar → the widgets.
        let avatar = studio.isEnabled && useAvatarOnHome
            ? viewModel.moodReading.flatMap { studio.image(for: $0.mood) }
            : nil
        WidgetSync.publish(viewModel, avatar: avatar)
    }

    /// New data types (heart rate, SpO₂, breathing, food) need a fresh
    /// Apple Health prompt; ask once, on first Home load after updating.
    private func requestHealthAccessIfNeeded() async {
        guard !askedForHealthAccess else { return }
        askedForHealthAccess = true
        if await HealthKitManager.shared.needsAuthorizationPrompt() {
            // Let the launch splash finish before the system sheet appears.
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            try? await HealthKitManager.shared.requestAuthorization()
        }
    }

    // MARK: - Header

    private var displayName: String {
        viewModel.firstName.trimmingCharacters(in: .whitespaces).ifEmpty("there")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                dayControl
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
                Text(showingToday ? "Here's your health today." : "Here's \(pastDayPhrase).")
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
                        .background(Circle().fill(Neka.surface.opacity(0.9)))
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

    // MARK: - Day control

    /// "‹  Tue, Oct 20  ›": step a day, or tap the date to jump to any day.
    /// The dashboard below changes in place.
    private var dayControl: some View {
        HStack(spacing: 6) {
            Button { step(-1) } label: {
                chevron("chevron.left", enabled: true)
            }
            .buttonStyle(.dialedScale)
            .accessibilityLabel("Previous day")
            Button { sheet = .pickDay } label: {
                HStack(spacing: 4) {
                    Text(showingToday ? viewModel.dateLine : selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(showingToday ? Neka.inkSecondary : Neka.ink)
                        .contentTransition(.numericText())
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to a day")
            Button { step(1) } label: {
                chevron("chevron.right", enabled: !showingToday)
            }
            .buttonStyle(.dialedScale)
            .disabled(showingToday)
            .accessibilityLabel("Next day")
            if !showingToday {
                Button { goToDay(Date()) } label: {
                    Text("Back to today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// "yesterday", or "Mon, Oct 19".
    private var pastDayPhrase: String {
        let label = DayNavigation.label(selectedDay)
        return label == "Yesterday" ? "yesterday" : label
    }

    private func chevron(_ icon: String, enabled: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(enabled ? Neka.ink : Neka.inkTertiary.opacity(0.5))
            .frame(width: 26, height: 26)
            .background(Circle().fill(Neka.surface.opacity(enabled ? 0.9 : 0.5)))
    }

    private func step(_ days: Int) {
        guard days < 0 || !showingToday else { return }
        goToDay(DayNavigation.step(selectedDay, by: days))
    }

    /// Shows `day` in place (no new screen), sliding the content the way you went.
    private func goToDay(_ day: Date) {
        let target = Calendar.current.startOfDay(for: min(day, Date()))
        guard target != selectedDay else { return }
        dayDirection = target < selectedDay ? -1 : 1
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { selectedDay = target }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Swipe right for the day before, left for the day after. Mostly
    /// horizontal drags only, so scrolling up and down is untouched.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.8 else { return }
                step(dx > 0 ? -1 : 1)
            }
    }

    // MARK: - What's below the header

    @ViewBuilder
    private var dayContent: some View {
        if showingToday {
            VStack(spacing: 16) {
                if let illness = signals.illness {
                    HomeIllnessBanner(check: illness, onOpen: { router.openHealth(.body) })
                }
                ForEach(layout.visible) { section in
                    sectionView(section)
                }
                exploreRow
                customizeButton
            }
        } else {
            // Swipes only here and on the header: today's cards have their
            // own horizontal scrollers that shouldn't change the day.
            DayRecapContent(date: selectedDay)
                .simultaneousGesture(daySwipe)
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = photos.thumbnail {
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
            .overlay(Circle().stroke(Neka.surface, lineWidth: 2))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

            Circle()
                .fill(GoogleHealthTokenStore.isConnected ? Neka.green : Neka.inkTertiary)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Neka.surface, lineWidth: 2))
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HomeHeroView(
            image: heroAvatar ?? photos.heroImage,
            isCutout: heroAvatar == nil && photos.hasCutout,
            isAvatar: heroAvatar != nil,
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
            onTapPhoto: { sheet = heroAvatar != nil ? .avatar : .profile },
            mood: viewModel.moodReading?.mood,
            moodScore: viewModel.moodReading?.score,
            onTapMood: { sheet = .avatar }
        )
    }

    /// Today's mood avatar, when you've made one and want it on Home.
    private var heroAvatar: UIImage? {
        guard useAvatarOnHome, let mood = viewModel.moodReading?.mood else { return nil }
        return studio.image(for: mood)
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
            Button { path.append(.weightTrend) } label: { weightTile }
                .buttonStyle(.dialedScale)
            Button { sheet = .water } label: { waterTile }
                .buttonStyle(.dialedScale)
            // These open the Health tab's deep-dive pages.
            Button { router.openHealth(.body) } label: { hrvTile }
                .buttonStyle(.dialedScale)
            Button { router.openHealth(.sleep) } label: { sleepTile }
                .buttonStyle(.dialedScale)
            Button { router.openHealth(.body) } label: { heartTile }
                .buttonStyle(.dialedScale)
            Button { router.openHealth(.body) } label: { activityTile }
                .buttonStyle(.dialedScale)
        }
    }

    private var weightTile: some View {
        let trend: [Double] = viewModel.progress?.series.suffix(30).map(\.trend)
            ?? WeightChallengeEngine.dailySeries(viewModel.weightReadings).suffix(30).map(\.trend)
        // The headline is the trend; the scale's reading sits underneath.
        let value: String = trend.last.map { String(format: "%.1f", $0) } ?? "--"
        var pill: (text: String, tint: Color, fill: Color)? = nil
        if let lost = viewModel.progress?.lostLbs {
            let amount = String(format: "%.1f", abs(lost))
            pill = lost >= 0
                ? (text: "−\(amount) lb", tint: Neka.green, fill: Neka.surface.opacity(0.85))
                : (text: "+\(amount) lb", tint: Neka.rose, fill: Neka.roseSoft)
        }
        var footer = "Connect your scale"
        if let scale = viewModel.latestWeight?.pounds {
            footer = "Scale \(String(format: "%.1f", scale))"
        } else if let start = viewModel.progress?.startWeight {
            footer = "Start \(String(format: "%.1f", start))"
        }
        var footerTrailing: String? = nil
        if let goal = viewModel.progress?.goalLossLbs {
            footerTrailing = "Goal −\(String(format: "%.0f", goal))"
        }

        return HomeMetricTile(
            title: "Trend weight",
            value: value,
            unit: "lb",
            wash: .mint,
            showsArrow: true,
            pill: pill,
            footer: footer,
            footerTrailing: footerTrailing
        ) {
            NekaSparkline(values: trend, color: Neka.green, fill: true)
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

    // MARK: - Sections (order and visibility from HomeLayout)

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        switch section {
        case .morning:
            if showsMorning {
                HomeMorningCard(
                    firstName: viewModel.firstName,
                    night: signals.lastNight,
                    recentNights: signals.nights,
                    readiness: signals.readiness,
                    weightReadings: viewModel.weightReadings,
                    mileStreak: viewModel.mileStreak,
                    progress: viewModel.progress,
                    friendName: viewModel.challenge?.friendDisplayName,
                    goalEvent: viewModel.goalEvent,
                    onWeighIn: { sheet = .weighIn },
                    onOpenSleep: { router.openHealth(.sleep) },
                    onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            morningDismissedDay = Self.dayKey(Date())
                        }
                    }
                )
                .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
            }
        case .wakeSuggestion:
            HomeWakeSuggestionCard()
        case .event:
            HomeEventCard(weightReadings: viewModel.weightReadings)
        case .finalPush:
            HomeFinalPushCard(challenge: viewModel.challenge, race: viewModel.race,
                              target: viewModel.calorieBudget, usualTarget: viewModel.finalPushUsualTarget)
        case .wrapped:
            HomeWrappedCard()
        case .hero:
            hero
        case .today:
            HomeDialedTodayCard(
                waterOz: viewModel.waterOz,
                waterTarget: viewModel.waterTargetOz,
                protein: viewModel.proteinGrams,
                proteinTarget: viewModel.proteinTarget,
                calories: viewModel.caloriesIn,
                calorieTarget: viewModel.calorieBudget,
                miles: viewModel.milesToday,
                onLogWater: { sheet = .water }
            )
        case .quests:
            HomeQuestsCard()
        case .sideBet:
            HomeSideBetCard(onOpen: { onOpenChallenge() })
        case .badges:
            HomeBadgesStrip()
        case .mile:
            HomeMileCard(
                miles: viewModel.milesToday,
                week: viewModel.milesWeek,
                streak: viewModel.mileStreak,
                ran: viewModel.ranToday,
                goal: viewModel.mileGoal
            )
            .onTapGesture { path.append(.mileHistory) }
        case .challenge:
            HomeChallengeCard(
                challenge: viewModel.challenge,
                progress: viewModel.progress,
                onSetUp: { sheet = .challengeSetup }
            )
            .onTapGesture {
                if viewModel.challenge != nil { onOpenChallenge() }
            }
        case .race:
            if let race = viewModel.race {
                RacePaceCard(report: race)
                    .onTapGesture { onOpenChallenge() }
            }
        case .futureYou:
            HomeFutureYouCard(
                event: viewModel.goalEvent,
                projection: viewModel.goalProjection,
                image: studio.futureImage ?? photos.thumbnail,
                onOpen: { sheet = .avatar }
            )
        case .workout:
            HomeWorkoutCard(onOpen: { path.append(.workout) }, onLog: { found in
                watchWorkouts = found
                sheet = .logWorkout
            })
        case .pulse:
            HomePulseCard(onOpen: { path.append(.pulse) })
        case .fun:
            HomeFunCard()
        case .suggestions:
            HomeRecentSuggestionsCard(onOpenDay: { goToDay($0) })
        case .tomorrow:
            if HomeTomorrowWakeCard.isShowing {
                HomeTomorrowWakeCard()
            }
        case .weeklyReview:
            if HomeWeeklyReviewCard.isShowing() {
                HomeWeeklyReviewCard(onOpen: { path.append(.weeklyReview) })
            }
        case .patterns:
            HomePatternCard(onOpenReview: { path.append(.weeklyReview) })
        case .paths:
            if !viewModel.pathScenarios.isEmpty {
                HomePathsCard(
                    scenarios: viewModel.pathScenarios,
                    targetDate: viewModel.pathTargetDate,
                    eventName: viewModel.goalEvent.flatMap { $0.date == viewModel.pathTargetDate ? $0.name : nil }
                )
            }
        case .aiBrief:
            if aiAvailability != .unsupportedDevice {
                AIBriefCard(
                    model: briefModel,
                    availability: aiAvailability,
                    onRegenerate: { Task { await briefModel.generate(viewModel.snapshot) } },
                    onAsk: { sheet = .ask }
                )
            }
        case .body:
            HomeStateStrip(items: stateItems)
            HomeBodyCheckCard(stress: signals.stress, illness: signals.illness,
                              onOpen: { router.openHealth(.body) })
        case .tiles:
            tiles
        case .fuel:
            HomeFuelCard(
                protein: viewModel.proteinGrams,
                proteinTarget: viewModel.proteinTarget,
                calories: viewModel.caloriesIn,
                calorieTarget: viewModel.calorieBudget,
                earned: viewModel.earned,
                onLogMeal: { sheet = .meal },
                onOpenLog: { path.append(.foodLog) },
                onEatingOut: { sheet = .eatingOut }
            )
        case .proteinPace:
            HomeProteinPaceCard(protein: viewModel.proteinGrams, target: viewModel.proteinTarget)
        case .mealPlan:
            HomeMealPlanCard(onOpen: { path.append(.mealPlan) })
        case .timeline:
            HomeTimelineCard(items: viewModel.timeline)
        case .coach:
            HomeCoachCard(insights: viewModel.insights)
        }
    }

    private var customizeButton: some View {
        Button { sheet = .customize } label: {
            Label("Customize Home", systemImage: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Neka.track))
        }
        .buttonStyle(.dialedScale)
    }

    /// One row to everything else (Food log, Trend weight, Schedule,
    /// Badges…), so Home stays short and nothing is hard to find.
    private var exploreRow: some View {
        Button { router.showDirectory = true } label: {
            moreLabel(icon: "square.grid.2x2.fill", title: "Everything in Dialed",
                      subtitle: "Food log, trend weight, schedule, badges and more",
                      tint: Neka.ink, fill: Neka.track)
                .nekaCard()
        }
        .buttonStyle(.dialedScale)
    }

    private func moreLabel(icon: String, title: String, subtitle: String, tint: Color, fill: Color) -> some View {
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

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .water:
            WaterLogSheet()
                .presentationDetents([.large])
        case .meal:
            AddFoodSheet()
                .presentationDetents([.large])
        case .eatingOut:
            EatingOutSheet()
                .presentationDetents([.large])
        case .ask:
            AskDialedSheet(snapshot: viewModel.snapshot)
                .presentationDetents([.large])
        case .avatar:
            AvatarSheet(
                reading: viewModel.moodReading ?? AvatarMood.read(viewModel.snapshot),
                projection: viewModel.goalProjection,
                onGoalChanged: { viewModel.refreshGoal() }
            )
            .presentationDetents([.large])
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
        case .customize:
            HomeLayoutEditor()
                .presentationDetents([.large])
        case .pickDay:
            DayPickerSheet(selection: selectedDay) { picked in goToDay(picked) }
            .presentationDetents([.medium, .large])
        case .logWorkout:
            WorkoutLoggerView(day: Calendar.current.startOfDay(for: Date()),
                              session: WorkoutPlanStore.session(on: Date()),
                              detected: watchWorkouts)
                .presentationDetents([.large])
        }
    }
}

/// Defers building a NavigationLink destination until it's shown.
struct LazyDestination<Content: View>: View {
    let build: () -> Content
    var body: some View { build() }
}

#Preview {
    HomeView()
        .environmentObject(AppRouter())
        .modelContainer(for: DialedSchema.allModels, inMemory: true)
}
