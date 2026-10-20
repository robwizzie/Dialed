//
//  ChallengeView.swift
//  Dialed
//
//  The weight-loss challenge tab: scoreboard against your friend, your
//  weight vs. goal pace, a trend projection to the final day, and what it
//  takes from here. Light Neka style to match Home.
//

import SwiftUI
import SwiftData
import Charts

@MainActor
final class ChallengeViewModel: ObservableObject {
    @Published var challenge: WeightChallenge?
    @Published var readings: [WeightReading] = []
    @Published var progress: WeightChallengeEngine.Progress?

    func refresh(context: ModelContext) async {
        let challenge = WeightChallenge.load()
        self.challenge = challenge
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -7, to: challenge?.startDate ?? today) ?? today
        readings = await WeightDataSource.readings(context: context, since: min(start, today))
        progress = challenge.map { WeightChallengeEngine.progress(challenge: $0, readings: readings) }
    }
}

struct ChallengeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ChallengeViewModel()

    @State private var sheet: Sheet?
    @ObservedObject private var liveSync = ChallengeSync.shared
    @EnvironmentObject private var router: AppRouter

    enum Sheet: String, Identifiable {
        case setup, edit, friend, weighIn, live
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let c = viewModel.challenge, let p = viewModel.progress {
                        scoreboard(c, p)
                        headToHead(c, p)
                        LiveChallengeCard(sync: liveSync, friendName: c.friendDisplayName) { sheet = .live }
                        TrashTalkCard(snapshot: trashTalkSnapshot(c, p))
                            .id("\(c.scoring.rawValue)-\(p.leader)-\(Int(p.margin * 10))")
                        chartCard(c, p)
                        paceCard(c, p)
                        weighInsCard(p)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .nekaPageBackground()
            .nekaStatusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.refresh(context: modelContext)
                await liveSync.sync(readings: viewModel.readings)
                // While the tab is open, pick up your friend's weigh-ins and messages.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                    guard !Task.isCancelled else { break }
                    await liveSync.sync(readings: viewModel.readings, force: true)
                }
            }
            .refreshable {
                await viewModel.refresh(context: modelContext)
                await liveSync.sync(readings: viewModel.readings, force: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: WeightChallenge.didChangeNotification)) { _ in
                Task { await viewModel.refresh(context: modelContext) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
                Task { await viewModel.refresh(context: modelContext) }
            }
            .onChange(of: router.challengeSheet) { _, request in
                guard let request else { return }
                sheet = request
                router.challengeSheet = nil
            }
            .sheet(item: $sheet, onDismiss: { Task { await viewModel.refresh(context: modelContext) } }) { sheet in
                switch sheet {
                case .setup:
                    ChallengeSetupSheet(existing: nil, suggestedStartWeight: viewModel.readings.last?.pounds)
                case .edit:
                    ChallengeSetupSheet(existing: viewModel.challenge, suggestedStartWeight: viewModel.progress?.startWeight)
                case .friend:
                    FriendWeighInSheet()
                        .presentationDetents([.medium])
                case .weighIn:
                    WeighInSheet(lastWeight: viewModel.readings.last?.pounds)
                        .presentationDetents([.medium])
                case .live:
                    if let c = viewModel.challenge {
                        LiveChallengeSheet(challenge: c, ownerStart: viewModel.progress?.startWeight, readings: viewModel.readings)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Challenge")
                    .font(Neka.display(34, weight: .bold))
                    .tracking(-0.8)
                    .foregroundColor(Neka.ink)
                if let c = viewModel.challenge {
                    Text("\(c.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(c.endDate.formatted(.dateTime.month(.abbreviated).day())) · vs. \(c.friendDisplayName)")
                        .font(.system(size: 14))
                        .foregroundColor(Neka.inkSecondary)
                } else {
                    Text("One month. Most weight lost wins.")
                        .font(.system(size: 14))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            Spacer()
            if viewModel.challenge != nil {
                Button { sheet = .weighIn } label: {
                    Label("Weigh in", systemImage: "scalemass.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                Button { sheet = .edit } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Neka.surface.opacity(0.9)))
                }
                .accessibilityLabel("Edit challenge")
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 18) {
            NekaIconBadge(systemName: "flag.2.crossed.fill", tint: Neka.orange, fill: Neka.surface, size: 72)
            Text("Set up your challenge")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Neka.ink)
            Text("Pick your friend, dates and goal. Dialed reads your scale, keeps score, and tells you exactly what today needs to look like to win.")
                .font(.system(size: 14))
                .foregroundColor(Neka.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Start challenge") { sheet = .setup }
                .buttonStyle(.nekaPrimary)
        }
        .padding(24)
        .nekaCard(wash: .peach)
        .padding(.top, 24)
    }

    // MARK: - Scoreboard

    private func scoreboard(_ c: WeightChallenge, _ p: WeightChallengeEngine.Progress) -> some View {
        HStack(spacing: 18) {
            ZStack {
                NekaMiniRing(progress: p.fractionElapsed, colors: [Neka.green, Color(hex: "9BE2AE")], lineWidth: 10)
                VStack(spacing: 0) {
                    Text(p.daysLeft > 0 ? "\(p.daysLeft)" : "✓")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Neka.ink)
                    Text(p.daysLeft == 1 ? "day left" : "days left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 6) {
                Text("You've lost")
                    .font(Neka.label)
                    .foregroundColor(Neka.inkSecondary)
                NekaValue(value: String(format: "%.1f", max(0, p.lostLbs)), unit: "lb", size: 44)
                Text(String(format: "%.1f%% of body weight", p.lostPercent))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                NekaProgressBar(progress: p.goalProgress, tint: Neka.green, height: 7)
                    .padding(.top, 4)
                Text(String(format: "%.0f%% of your −%.0f lb goal", p.goalProgress * 100, p.goalLossLbs))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard(wash: .mint)
    }

    // MARK: - Head to head

    private func headToHead(_ c: WeightChallenge, _ p: WeightChallengeEngine.Progress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Head to head")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                Text(c.scoring == .percent ? "Scored by %" : "Scored by lbs")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }

            HStack(spacing: 12) {
                competitor(
                    name: "You",
                    start: p.startWeight,
                    current: p.currentWeight,
                    lostLbs: p.startWeight != nil && p.currentWeight != nil ? p.lostLbs : nil,
                    lostPct: p.startWeight != nil && p.currentWeight != nil ? p.lostPercent : nil,
                    isLeader: p.leader == .you,
                    tint: Neka.green
                )
                competitor(
                    name: c.friendDisplayName,
                    start: p.friend?.startWeight,
                    current: p.friend?.currentWeight,
                    lostLbs: p.friend?.lostLbs,
                    lostPct: p.friend?.lostPercent,
                    isLeader: p.leader == .friend,
                    tint: Neka.orange
                )
            }

            // When live, their weigh-ins come from the shared page / their scale.
            if !liveSync.isLive {
                Button { sheet = .friend } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Log \(c.friendDisplayName)'s weigh-in")
                        Spacer()
                        if let last = p.friend?.lastWeighIn {
                            Text(last.formatted(.relative(presentation: .named)))
                                .foregroundColor(Neka.inkTertiary)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func competitor(
        name: String,
        start: Double?,
        current: Double?,
        lostLbs: Double?,
        lostPct: Double?,
        isLeader: Bool,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                if isLeader {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.amber)
                }
            }
            Text(lostPct.map { String(format: "%.1f%%", $0) } ?? "—")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text(lostLbs.map { String(format: "%.1f lb lost", $0) } ?? "No weigh-ins")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
            Divider().overlay(Neka.hairline)
            HStack {
                stat("Start", start)
                Spacer()
                stat("Now", current)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isLeader ? tint.opacity(0.12) : Neka.track)
        )
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkTertiary)
            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.ink)
        }
    }

    // MARK: - Trash talk

    private func trashTalkSnapshot(_ c: WeightChallenge, _ p: WeightChallengeEngine.Progress) -> HealthSnapshot {
        var s = HealthSnapshot()
        s.firstName = UserDefaults.standard.string(forKey: "user.firstName") ?? ""
        s.friendName = c.friendDisplayName
        s.challengeDay = p.dayNumber
        s.challengeDays = p.totalDays
        s.daysLeft = p.daysLeft
        s.scoring = c.scoring
        if p.startWeight != nil && p.currentWeight != nil {
            s.lostLbs = p.lostLbs
            s.lostPercent = p.lostPercent
        }
        s.friendLostLbs = p.friend?.lostLbs
        s.friendLostPercent = p.friend?.lostPercent
        s.leader = p.leader
        s.margin = p.margin
        s.goalLossLbs = p.goalLossLbs
        s.weighedInToday = p.weighedInToday
        return s
    }

    // MARK: - Chart

    private func chartCard(_ c: WeightChallenge, _ p: WeightChallengeEngine.Progress) -> some View {
        let window = p.series.filter { $0.day >= Calendar.current.startOfDay(for: c.startDate).addingTimeInterval(-3 * 86_400) }
        let values = window.map(\.pounds) + [p.startWeight, p.startWeight.map { $0 - c.goalLossLbs }].compactMap { $0 }
        let lo = (values.min() ?? 0) - 1
        let hi = (values.max() ?? 1) + 1

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight vs. goal pace")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                legendDot(Neka.green, "Trend")
                legendDot(Neka.inkTertiary, "Pace")
            }

            if window.isEmpty {
                Text("No weigh-ins yet. Step on your scale — readings from Apple Health or Fitbit show up here automatically.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                Chart {
                    if let start = p.startWeight {
                        LineMark(x: .value("Day", c.startDate), y: .value("Pace", start), series: .value("Line", "pace"))
                            .foregroundStyle(Neka.inkTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        LineMark(x: .value("Day", c.endDate), y: .value("Pace", start - c.goalLossLbs), series: .value("Line", "pace"))
                            .foregroundStyle(Neka.inkTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    }
                    ForEach(window) { d in
                        PointMark(x: .value("Day", d.day), y: .value("Weight", d.pounds))
                            .foregroundStyle(Neka.green.opacity(0.35))
                            .symbolSize(28)
                        LineMark(x: .value("Day", d.day), y: .value("Weight", d.trend), series: .value("Line", "trend"))
                            .foregroundStyle(Neka.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    RuleMark(x: .value("Today", Date()))
                        .foregroundStyle(Neka.ink.opacity(0.15))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartYScale(domain: lo...hi)
                .chartXScale(domain: min(window.first?.day ?? c.startDate, c.startDate)...c.endDate)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Neka.hairline)
                        AxisValueLabel().foregroundStyle(Neka.inkTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(Neka.inkTertiary)
                    }
                }
                .frame(height: 200)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
        }
    }

    // MARK: - Pace

    private func paceCard(_ c: WeightChallenge, _ p: WeightChallengeEngine.Progress) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 14) {
            Text("Pace")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                paceStat(
                    "Vs. pace",
                    p.paceDelta >= 0 ? String(format: "+%.1f lb", p.paceDelta) : String(format: "%.1f lb", p.paceDelta),
                    p.paceDelta >= 0 ? "ahead" : "behind",
                    p.paceDelta >= 0 ? Neka.green : Neka.orange
                )
                paceStat(
                    "Projected finish",
                    p.projectedLossAtEnd.map { String(format: "−%.1f lb", max(0, $0)) } ?? "—",
                    p.projectedLossAtEnd == nil ? "needs 3+ weigh-ins" : "if the trend holds",
                    Neka.ink
                )
                paceStat(
                    "Weekly rate",
                    p.weeklyRate.map { String(format: "%.1f lb", $0) } ?? "—",
                    "1–2 lb/week is sustainable",
                    Neka.ink
                )
                paceStat(
                    "Daily deficit needed",
                    p.requiredDailyDeficit > 0 ? "\(Int((p.requiredDailyDeficit / 10).rounded() * 10)) kcal" : "Goal hit",
                    p.requiredDailyDeficit > 1_000 ? "aggressive — be safe" : "to reach −\(Int(c.goalLossLbs)) lb",
                    p.requiredDailyDeficit > 1_000 ? Neka.rose : Neka.ink
                )
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func paceStat(_ title: String, _ value: String, _ note: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(tint)
            Text(note)
                .font(.system(size: 10))
                .foregroundColor(Neka.inkTertiary)
                .lineLimit(2)
        }
    }

    // MARK: - Weigh-ins

    private func weighInsCard(_ p: WeightChallengeEngine.Progress) -> some View {
        let recent = Array(p.series.suffix(7).reversed())
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weigh-ins")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                if p.weighInStreak > 1 {
                    NekaPill(text: "🔥 \(p.weighInStreak)-day streak", tint: Neka.orange, fill: Neka.orangeSoft)
                }
            }
            if recent.isEmpty {
                Text("Nothing yet.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, day in
                let previous = index + 1 < recent.count ? recent[index + 1].pounds : nil
                HStack {
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 13))
                        .foregroundColor(Neka.ink)
                    Spacer()
                    if let previous {
                        let delta = day.pounds - previous
                        Text(String(format: "%@%.1f", delta <= 0 ? "−" : "+", abs(delta)))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(delta <= 0 ? Neka.green : Neka.rose)
                    }
                    Text(String(format: "%.1f lb", day.pounds))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(width: 76, alignment: .trailing)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .nekaCard()
    }
}

// MARK: - Friend weigh-in

struct FriendWeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var challenge: WeightChallenge? = WeightChallenge.load()
    @State private var pounds: Double = 0
    @State private var date: Date = Date()

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Neka.muted)
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            Text("\(challenge?.friendDisplayName ?? "Friend")'s weigh-in")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Neka.ink)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0.0", value: $pounds, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .frame(maxWidth: 220)
                Text("lb")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }

            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                .foregroundColor(Neka.ink)
                .padding(.horizontal, 4)

            Spacer(minLength: 0)

            Button("Save") { save() }
                .buttonStyle(.nekaPrimary)
                .disabled(pounds < 50)
                .opacity(pounds < 50 ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(Neka.paper.ignoresSafeArea())
        .onAppear {
            let last = challenge?.friendWeighIns.max(by: { $0.date < $1.date })?.pounds
            pounds = last ?? challenge?.friendStartWeight ?? 0
        }
    }

    private func save() {
        guard var c = challenge, pounds >= 50 else { return }
        c.friendWeighIns.append(.init(date: date, pounds: pounds))
        if c.friendStartWeight == nil, c.friendWeighIns.count == 1 {
            c.friendStartWeight = pounds
        }
        c.save()
        dismiss()
    }
}
