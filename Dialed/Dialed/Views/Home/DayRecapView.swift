//
//  DayRecapView.swift
//  Dialed
//
//  A past day, shown right on Home when you step back with the header's
//  date control: the Dialed score, the night before, food, protein and
//  water against target, the mile, workouts, calories earned, suggested
//  activity, the weigh-in and quests. Every card fills in on its own as
//  its data arrives (DayRecapStore), and anything still waiting from that
//  day (an unnamed stretch, a watch session you never logged) can be
//  reviewed and added here.
//

import SwiftUI
import SwiftData

struct DayRecapContent: View {
    let date: Date

    @Environment(\.modelContext) private var context
    @ObservedObject private var store = DayRecapStore.shared
    @State private var naming: HomeFunCard.NamingTarget?
    @State private var reviewing: ActiveBouts.Bout?
    @State private var logging: DetectedWorkout?

    private var day: DayRecapStore.Day? { store.day(date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            scoreCard
            if let items = day?.suggestions, !items.isEmpty { suggestionsCard(items) }
            sleepCard
            fuelCard
            moveCard
            extrasCard
        }
        .task(id: "\(DayLoadKit.key(date))-\(store.version)") {
            await store.load(date, context: context)
        }
        .sheet(item: $naming) { target in
            FunActivitySheet(target: target) { RecentSuggestions.invalidate() }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $reviewing) { bout in
            ActivityReviewSheet(bout: bout)
                .presentationDetents([.large])
        }
        .sheet(item: $logging, onDismiss: { RecentSuggestions.invalidate() }) { w in
            WorkoutLoggerView(day: date, session: WorkoutPlanStore.session(on: date), detected: [w])
                .presentationDetents([.large])
        }
    }

    // MARK: - Score

    private var dialedScore: Int? {
        guard let d = day else { return nil }
        let budget = d.calorieTarget + (d.earned?.earned ?? 0)
        return DialedScore.compute(waterOz: d.waterOz, waterTargetOz: d.waterTarget, protein: d.protein,
                                   proteinTarget: d.proteinTarget, calories: d.calories,
                                   calorieTarget: budget, miles: d.miles)
    }

    private var scoreCard: some View {
        let score = dialedScore ?? 0
        let color = score >= 80 ? Neka.green : score >= 55 ? Neka.amber : Neka.rose
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Neka.track, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(dialedScore.map(String.init) ?? "–")
                        .font(Neka.display(30, weight: .bold))
                        .foregroundColor(Neka.ink)
                        .contentTransition(.numericText(value: Double(score)))
                    Text("DIALED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text(dialedScore == nil ? "Pulling that day together…" : Self.verdict(score))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = day?.pillars {
                    HStack(spacing: 6) {
                        pillar("Recovery", p.recovery)
                        pillar("Readiness", p.readiness)
                        pillar("Strain", p.strain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .nekaCard(wash: .mint)
        .animation(.easeOut(duration: 0.25), value: dialedScore)
    }

    static func verdict(_ score: Int) -> String {
        switch score {
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

    private func suggestionsCard(_ items: [DaySuggestions.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Still waiting from this day", systemImage: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
            ForEach(items) { item in
                SuggestionRow(item: item, showsDay: false,
                              onOpen: item.bout.map { b -> () -> Void in { reviewing = b } },
                              onAdd: { add(item) },
                              onDismiss: {
                                  RecentSuggestions.dismiss(item)
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
        if let night = day?.night {
            row(icon: "moon.stars.fill", tint: Neka.lavender, fill: Neka.lavenderSoft,
                title: "Slept \(Self.hours(night.asleepMinutes))",
                detail: "\(night.bedtime.formatted(date: .omitted, time: .shortened)) → \(night.wakeTime.formatted(date: .omitted, time: .shortened)) · score \(HealthInsights.sleepScore(night))"
                    + (night.vendorScore.map { " · Google \($0)" } ?? ""))
                .padding(14)
                .nekaCard()
        } else if day != nil {
            row(icon: "moon.zzz", tint: Neka.inkTertiary, fill: Neka.track,
                title: "No sleep recorded", detail: "Nothing synced for the night before")
                .padding(14)
                .nekaCard()
        }
    }

    // MARK: - Food

    private var fuelCard: some View {
        let d = day ?? DayRecapStore.Day()
        let budget = d.calorieTarget + (d.earned?.earned ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fuel")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                if day?.loaded.contains(.health) == false {
                    ProgressView().controlSize(.mini)
                }
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
            bar("Calories", d.calories, budget, unit: "", tint: d.calories > budget ? Neka.rose : Neka.green)
            bar("Protein", d.protein, d.proteinTarget, unit: " g", tint: Neka.orange)
            bar("Water", d.waterOz, d.waterTarget, unit: " oz", tint: Neka.sky)
            if let earned = d.earned, earned.earned > 0 {
                Text("Budget includes +\(Int(earned.earned)) calories earned (\(earned.sources)).")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(16)
        .nekaCard()
        .redacted(reason: day == nil ? .placeholder : [])
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
        let d = day ?? DayRecapStore.Day()
        let mi = d.miles ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Move")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                if let d = day, !d.loaded.isSuperset(of: [.watch, .earned, .activity]) {
                    ProgressView().controlSize(.mini)
                }
            }
            row(icon: "figure.walk", tint: Neka.lavenderText, fill: Neka.lavenderSoft,
                title: mi >= MileADay.goal ? "Mile done · \(String(format: "%.1f", mi)) mi" : String(format: "%.2f mi", mi),
                detail: [mi >= MileADay.goal ? "Streak kept alive" : "Short of the mile",
                         d.steps.map { "\(Int($0).formatted()) steps" }].compactMap { $0 }.joined(separator: " · "))
            if let title = d.workoutTitle {
                row(icon: "dumbbell.fill", tint: Neka.greenText, fill: Neka.greenSoft,
                    title: title, detail: d.setsDone > 0 ? "\(d.setsDone) sets logged" : "Logged")
            }
            ForEach(d.watch ?? []) { w in
                row(icon: w.isCardio ? WorkoutLoggerView.cardioSymbol(WorkoutDetector.title(for: w.kind)) : "applewatch",
                    tint: Neka.sky, fill: Neka.skySoft, title: "\(w.title) · \(Int(w.minutes.rounded())) min",
                    detail: [w.timeText, w.calories.map { "\($0) cal" }, w.source].compactMap { $0 }.joined(separator: " · "))
            }
            ForEach(d.moments ?? []) { m in
                row(icon: ActiveBouts.symbol(for: m.name), tint: Neka.orangeText, fill: Neka.orangeSoft,
                    title: m.name,
                    detail: "\(m.start.formatted(date: .omitted, time: .shortened)) · \(Int(m.minutes)) min" + (m.calories.map { " · ~\(Int($0)) cal" } ?? ""))
            }
            if let earned = d.earned, earned.earned > 0 {
                Label("+\(Int(earned.earned)) calories earned", systemImage: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.orangeText)
            }
            if let d = day, !d.failed.intersection([.watch, .earned, .activity]).isEmpty {
                Text("Some watch data didn't come back in time. Pull down to try again.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .padding(16)
        .nekaCard()
        .redacted(reason: day == nil ? .placeholder : [])
    }

    // MARK: - Extras

    @ViewBuilder
    private var extrasCard: some View {
        let weighIn = day?.weighIn ?? nil
        let quests = day?.quests
        if weighIn != nil || quests != nil {
            VStack(spacing: 10) {
                if let w = weighIn {
                    row(icon: "scalemass.fill", tint: Neka.greenText, fill: Neka.greenSoft,
                        title: String(format: "Weighed in at %.1f lb", w), detail: "That morning's weigh-in")
                }
                if let q = quests {
                    row(icon: "checklist.checked", tint: Neka.amber, fill: Neka.amberSoft,
                        title: "\(q.done) of 3 quests", detail: "+\(q.xp) XP")
                }
            }
            .padding(14)
            .nekaCard()
        }
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
}

// MARK: - Shared pieces

/// One waiting item: "Active 58 min · 4:12 PM · ~560 cal   [Name it] ✕".
/// Tapping the row itself (when `onOpen` is set) opens a closer look.
struct SuggestionRow: View {
    let item: DaySuggestions.Item
    var showsDay = true
    var onOpen: (() -> Void)? = nil
    var onAdd: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let onOpen {
                Button(action: onOpen) { summary.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Review the heart rate")
            } else {
                summary
            }
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

    private var summary: some View {
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
