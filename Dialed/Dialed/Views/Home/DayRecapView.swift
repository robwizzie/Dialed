//
//  DayRecapView.swift
//  Dialed
//
//  Any past day at a glance: the Dialed score, the night before, food,
//  protein and water against target, the mile, workouts, calories earned,
//  the weigh-in, bonus burn and quests. Step a day with the chevrons
//  or a swipe, or jump with the calendar. Anything still waiting from that
//  day (an unnamed stretch, a watch session you never logged) can be
//  added right here.
//

import SwiftUI
import SwiftData

struct DayRecapView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var model = HealthDetailModel()
    @State private var date: Date
    @State private var picking = false
    @State private var loading = true

    @State private var miles: Double?
    @State private var snapshot: DailyScoreSnapshot?
    @State private var workoutLog: PlanWorkoutLog?
    @State private var setsDone = 0
    @State private var watchWorkouts: [DetectedWorkout] = []
    @State private var earned = EarnedCalories.Day()
    @State private var active: [ContextEvent] = []
    @State private var quests: (done: Int, xp: Int)?
    @State private var suggestions: [DaySuggestions.Item] = []
    @State private var naming: HomeFunCard.NamingTarget?
    @State private var logging: DetectedWorkout?

    private let calendar = Calendar.current

    init(date: Date) {
        _date = State(initialValue: Calendar.current.startOfDay(for: date))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dayBar
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    scoreCard
                    if !suggestions.isEmpty { suggestionsCard }
                    sleepCard
                    fuelCard
                    moveCard
                    if quests != nil || weighIn != nil { extrasCard }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle(DayNavigation.label(date))
        .navigationBarTitleDisplayMode(.inline)
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            if value.translation.width > 60 { step(-1) }
            if value.translation.width < -60, DayNavigation.canGoForward(date) { step(1) }
        })
        .task(id: date) { await load() }
        .sheet(isPresented: $picking) {
            DayPickerSheet(selection: date) { picked in
                withAnimation { date = calendar.startOfDay(for: picked) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $naming) { target in
            FunActivitySheet(target: target) {
                RecentSuggestions.invalidate()
                Task { await load() }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $logging, onDismiss: {
            RecentSuggestions.invalidate()
            Task { await load() }
        }) { w in
            WorkoutLoggerView(day: date, session: WorkoutPlanStore.session(on: date), detected: [w])
                .presentationDetents([.large])
        }
    }

    private func step(_ days: Int) {
        withAnimation(.easeOut(duration: 0.2)) { date = DayNavigation.step(date, by: days) }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    // MARK: - Day bar

    private var dayBar: some View {
        HStack(spacing: 10) {
            chevron("chevron.left", enabled: true) { step(-1) }
                .accessibilityLabel("Previous day")
            Button { picking = true } label: {
                VStack(spacing: 2) {
                    Text(DayNavigation.label(date))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Neka.ink)
                    Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Pick a day")
            chevron("chevron.right", enabled: DayNavigation.canGoForward(date)) { step(1) }
                .accessibilityLabel("Next day")
        }
    }

    private func chevron(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(enabled ? Neka.ink : Neka.inkTertiary)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Neka.surface))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        }
        .buttonStyle(.dialedScale)
        .disabled(!enabled)
    }

    // MARK: - Score

    private var dialedScore: Int {
        let n = model.nutrition
        return DialedScore.compute(waterOz: n.waterOz, waterTargetOz: n.waterTargetOz, protein: n.protein,
                                   proteinTarget: n.proteinTarget, calories: n.calories,
                                   calorieTarget: n.calorieTarget + earned.earned, miles: miles)
    }

    private var scoreCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Neka.track, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(dialedScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(dialedScore)")
                        .font(Neka.display(30, weight: .bold))
                        .foregroundColor(Neka.ink)
                        .contentTransition(.numericText(value: Double(dialedScore)))
                    Text("DIALED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text(verdict)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let s = snapshot {
                    HStack(spacing: 6) {
                        pillar("Recovery", s.recoveryScore)
                        pillar("Readiness", s.readinessScore)
                        pillar("Strain", s.strainScore)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .nekaCard(wash: .mint)
    }

    private var scoreColor: Color {
        dialedScore >= 80 ? Neka.green : dialedScore >= 55 ? Neka.amber : Neka.rose
    }

    private var verdict: String {
        switch dialedScore {
        case 85...: return "Dialed in. That's the blueprint."
        case 70..<85: return "Solid day with a little left on the table."
        case 50..<70: return "Half there. Water, protein and the mile add up."
        default: return "An off day. They happen. The next one counts more."
        }
    }

    private func pillar(_ name: String, _ value: Int?) -> some View {
        VStack(spacing: 1) {
            Text(value.map(String.init) ?? "–")
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Neka.ink)
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Neka.surface.opacity(0.8)))
    }

    // MARK: - Suggestions

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Still waiting from this day", systemImage: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
            ForEach(suggestions) { item in
                SuggestionRow(item: item, showsDay: false, onAdd: { add(item) }, onDismiss: {
                    RecentSuggestions.dismiss(item)
                    withAnimation { suggestions.removeAll { $0.id == item.id } }
                })
            }
        }
        .padding(16)
        .nekaCard(wash: .peach)
    }

    private func add(_ item: DaySuggestions.Item) {
        switch item.kind {
        case .activity: if let b = item.bout { naming = .bout(b) }
        case .workout:  logging = item.workout
        }
    }

    // MARK: - Sleep

    @ViewBuilder
    private var sleepCard: some View {
        if let night = model.lastNight {
            let score = HealthInsights.sleepScore(night)
            row(icon: "moon.stars.fill", tint: Neka.lavender, fill: Neka.lavenderSoft,
                title: "Slept \(Self.hours(night.asleepMinutes))",
                detail: "\(night.bedtime.formatted(date: .omitted, time: .shortened)) → \(night.wakeTime.formatted(date: .omitted, time: .shortened)) · score \(score)")
                .padding(14)
                .nekaCard()
        }
    }

    // MARK: - Food

    private var fuelCard: some View {
        let n = model.nutrition
        let budget = n.calorieTarget + earned.earned
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fuel")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                NavigationLink {
                    FoodLogView(day: date)
                } label: {
                    Label("Food log", systemImage: "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Neka.track))
                }
            }
            bar("Calories", n.calories, budget, unit: "", tint: n.calories > budget ? Neka.rose : Neka.green)
            bar("Protein", n.protein, n.proteinTarget, unit: " g", tint: Neka.orange)
            bar("Water", n.waterOz, n.waterTargetOz, unit: " oz", tint: Neka.sky)
            if earned.earned > 0 {
                Text("Budget includes +\(Int(earned.earned)) calories earned (\(earned.sources)).")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func bar(_ title: String, _ value: Double, _ target: Double, unit: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
                Text("\(Int(value).formatted()) / \(Int(target).formatted())\(unit)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Neka.ink)
            }
            NekaProgressBar(progress: target > 0 ? value / target : 0, tint: tint, height: 7)
        }
    }

    // MARK: - Move

    private var moveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            let mi = miles ?? 0
            row(icon: "figure.walk", tint: Neka.lavenderText, fill: Neka.lavenderSoft,
                title: mi >= MileADay.goal ? "Mile done · \(String(format: "%.1f", mi)) mi" : String(format: "%.2f mi", mi),
                detail: mi >= MileADay.goal ? "Streak kept alive" : "Short of the mile")
            if let log = workoutLog {
                row(icon: "dumbbell.fill", tint: Neka.greenText, fill: Neka.greenSoft,
                    title: log.title, detail: setsDone > 0 ? "\(setsDone) sets logged" : "Logged")
            }
            ForEach(watchWorkouts) { w in
                row(icon: w.isCardio ? WorkoutLoggerView.cardioSymbol(WorkoutDetector.title(for: w.kind)) : "applewatch",
                    tint: Neka.sky, fill: Neka.skySoft, title: "\(w.title) · \(Int(w.minutes.rounded())) min",
                    detail: [w.timeText, w.calories.map { "\($0) cal" }, w.source].compactMap { $0 }.joined(separator: " · "))
            }
            ForEach(active, id: \.id) { e in
                row(icon: ActiveBouts.symbol(for: e.text ?? ""), tint: Neka.orangeText, fill: Neka.orangeSoft,
                    title: e.text ?? "Activity",
                    detail: "\(e.timestamp.formatted(date: .omitted, time: .shortened)) · \(Int(e.value ?? 0)) min" + (e.secondaryValue.map { " · ~\(Int($0)) cal" } ?? ""))
            }
            if earned.earned > 0 {
                Label("+\(Int(earned.earned)) calories earned", systemImage: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.orangeText)
            }
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Extras

    private var weighIn: Double? {
        model.weight.first { calendar.isDate($0.date, inSameDayAs: date) }?.value
    }

    private var extrasCard: some View {
        VStack(spacing: 10) {
            if let w = weighIn {
                row(icon: "scalemass.fill", tint: Neka.greenText, fill: Neka.greenSoft,
                    title: String(format: "Weighed in at %.1f lb", w), detail: "Morning weigh-in")
            }
            if let q = quests {
                row(icon: "checklist.checked", tint: Neka.amber, fill: Neka.amberSoft,
                    title: "\(q.done) of 3 quests", detail: "+\(q.xp) XP")
            }
        }
        .padding(14)
        .nekaCard()
    }

    private func row(icon: String, tint: Color, fill: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(fill))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    static func hours(_ minutes: Int) -> String { "\(minutes / 60)h \(minutes % 60)m" }

    // MARK: - Load

    private func load() async {
        let day = date
        loading = snapshot == nil && workoutLog == nil && model.nights.isEmpty
        model.day = day
        await model.load(context: context)
        guard day == date else { return }

        miles = MileHistory.load()?.day(day)?.miles
        let snapshots = (try? context.fetch(FetchDescriptor<DailyScoreSnapshot>(predicate: #Predicate { $0.logicalDate == day }))) ?? []
        snapshot = snapshots.first
        workoutLog = PlanWorkoutLogStore.log(for: WorkoutPlanStore.key(day), context: context)
        setsDone = workoutLog.map { PlanWorkoutLogStore.sets(for: $0.id, context: context).filter(\.completed).count } ?? 0
        watchWorkouts = await WorkoutDetector.workouts(on: day, context: context)
        earned = await EarnedCalories.day(day, context: context)
        active = await FunActivityService.day(day, context: context).logged
        if let q = GameStore.load().days[WeeklyReview.dayKey(day)], !q.done.isEmpty {
            quests = (q.done.count, q.done.values.reduce(0, +) + (q.swept ? QuestEngine.sweepBonus : 0))
        } else {
            quests = nil
        }
        suggestions = calendar.isDateInToday(day) ? [] : await RecentSuggestions.forDay(day, context: context)
        guard day == date else { return }
        withAnimation(.easeOut(duration: 0.2)) { loading = false }
    }
}

// MARK: - Shared pieces

/// One waiting item: "Active 58 min · 4:12 PM · ~560 cal   [Add] ✕".
struct SuggestionRow: View {
    let item: DaySuggestions.Item
    var showsDay = true
    var onAdd: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .activity ? "waveform.path.ecg" : "applewatch")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(item.kind == .activity ? Neka.rose : Neka.sky)
                .frame(width: 38, height: 38)
                .background(Circle().fill(item.kind == .activity ? Neka.roseSoft : Neka.skySoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onAdd) {
                Text(item.kind == .activity ? "Name it" : "Log it")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.onInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Neka.ink))
            }
            .buttonStyle(.dialedScale)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Neka.track))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }

    private var detail: String {
        var parts: [String] = []
        if showsDay { parts.append(DayNavigation.label(item.day)) }
        parts.append(item.start.formatted(date: .omitted, time: .shortened))
        if let c = item.calories, c > 0 { parts.append("~\(Int(c)) cal") }
        return parts.joined(separator: " · ")
    }
}

/// Jump to any past day.
struct DayPickerSheet: View {
    @State var selection: Date
    var onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Day", selection: $selection, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Neka.green)
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .navigationTitle("Go to a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Today") {
                        onPick(Date())
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        onPick(selection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
