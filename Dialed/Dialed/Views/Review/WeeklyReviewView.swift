//
//  WeeklyReviewView.swift
//  Dialed
//
//  The Sunday weekly review: one screen for a Monday–Sunday week —
//  the one thing to fix next week, the weight trend, averages against
//  your targets, days on target, best and toughest day, and where the
//  trend lands you on your goal day. Step back through past weeks with
//  the chevrons. Opened from Home (Sundays & Mondays), the "Go to" menu
//  and the Sunday 6 PM reminder.
//

import SwiftUI
import SwiftData
import Charts

struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var model = WeeklyReviewModel()
    @State private var sundayReminderOn = ReminderSettings.load().isOn(.weeklyReview)
    @State private var permissionDenied = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let s = model.summary {
                    VStack(alignment: .leading, spacing: 16) {
                        if s.scores.isEmpty {
                            emptyCard
                        } else {
                            fixCard
                            weightCard(s)
                            HealthTileGrid { tiles(s) }
                            dayByDayCard(s)
                        }
                        if !model.patterns.isEmpty {
                            patternsSection
                        }
                        goalCard(s)
                        trophyLinks
                    }
                    .nekaLoading(showsOtherWeek)
                } else {
                    NekaLoadingPage(cards: [150, 200, 190, 220])
                }
                if !sundayReminderOn {
                    reminderPrompt
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .nekaPageBackground()
        .navigationTitle("Week in review")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.weeksBack) {
            await model.load(context: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
            Task { await model.load(context: modelContext) }
        }
    }

    /// Mid-flip to another week: the old week's cards stay up, redacted,
    /// until the new one lands (rather than showing the wrong week's numbers).
    private var showsOtherWeek: Bool {
        guard let s = model.summary else { return false }
        return s.start != model.range.start
    }

    /// Badges and the habit heatmap.
    private var trophyLinks: some View {
        VStack(spacing: 0) {
            NavigationLink { BadgesView() } label: {
                trophyRow("medal.fill", "Badges", "Your trophy wall and what's next", Neka.amber, Neka.amberSoft)
            }
            Divider().overlay(Neka.hairline).padding(.leading, 62)
            NavigationLink { HabitHeatmapView() } label: {
                trophyRow("square.grid.3x3.fill", "Habit heatmap", "Twelve weeks of mile, protein, logging and workouts", Neka.green, Neka.greenSoft)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .nekaCard()
    }

    private func trophyRow(_ icon: String, _ title: String, _ subtitle: String, _ tint: Color, _ fill: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(fill))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NekaPill(text: weekLabel.uppercased(), tint: Neka.lavender, fill: Neka.surface.opacity(0.85))
                Spacer()
                weekButton("chevron.left", enabled: model.weeksBack < WeeklyReviewModel.maxWeeksBack) { model.shift(1) }
                weekButton("chevron.right", enabled: model.weeksBack > 0) { model.shift(-1) }
            }
            Text(model.rangeTitle)
                .font(Neka.display(30, weight: .bold))
                .tracking(-0.6)
                .foregroundColor(Neka.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard(wash: .lavender)
    }

    private var weekLabel: String {
        if model.weeksBack == 0 {
            return calendar.component(.weekday, from: Date()) == 1 ? "This week" : "Last week"
        }
        let isSunday = calendar.component(.weekday, from: Date()) == 1
        let back = model.weeksBack + (isSunday ? 0 : 1)
        return back == 1 ? "Last week" : "\(back) weeks ago"
    }

    private var subtitle: String {
        guard let s = model.summary else { return "Loading your week…" }
        var parts: [String] = []
        if let avg = s.averageScore { parts.append("Avg day score \(avg)") }
        parts.append("\(s.scores.count) of 7 days with data")
        return parts.joined(separator: " · ")
    }

    private func weekButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(enabled ? Neka.ink : Neka.inkTertiary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Neka.surface.opacity(0.9)))
        }
        .buttonStyle(.dialedScale)
        .disabled(!enabled)
    }

    // MARK: - Patterns

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Patterns")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                Text("Last 5 weeks")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
            }
            ForEach(model.patterns.prefix(5)) { p in
                PatternRow(pattern: p)
            }
        }
    }

    // MARK: - One thing to fix

    @ViewBuilder
    private var fixCard: some View {
        if let fix = model.fix {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: model.fixIsAI ? "sparkles" : icon(for: fix.area))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.fixIsAI
                            ? AnyShapeStyle(LinearGradient(colors: Neka.intelligence, startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Neka.orange))
                    Text("ONE THING TO FIX NEXT WEEK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Spacer()
                    if model.isThinking {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(fix.headline)
                    .font(Neka.display(22, weight: .bold))
                    .foregroundColor(Neka.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fix.detail)
                    .font(.system(size: 14))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.fixIsAI {
                    Text("Apple Intelligence · on-device")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nekaCard(wash: .peach)
        }
    }

    private func icon(for area: WeeklyReview.FixArea) -> String {
        switch area {
        case .logging:  return "square.and.pencil"
        case .calories: return "flame.fill"
        case .protein:  return "fork.knife"
        case .water:    return "drop.fill"
        case .steps:    return "figure.walk"
        case .sleep:    return "moon.fill"
        case .weighIn:  return "scalemass.fill"
        case .none:     return "checkmark.seal.fill"
        }
    }

    // MARK: - Weight

    private func weightCard(_ s: WeeklyReview.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthCardHeader(title: "Weight trend", trailing: "smoothed")
            if let change = s.weightChange {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text((change > 0 ? "+" : (change < 0 ? "−" : "")) + String(format: "%.1f", abs(change)))
                        .font(Neka.display(34, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("lb this week")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                    Spacer()
                    if let rate = s.weeklyRate {
                        let losing = rate < 0
                        NekaPill(text: String(format: "%.1f lb/wk", abs(rate)) + (losing ? " ↓" : " ↑"),
                                 tint: losing ? Neka.green : Neka.rose,
                                 fill: losing ? Neka.greenSoft : Neka.roseSoft)
                    }
                }
                if let a = s.weightStart, let b = s.weightEnd {
                    Text(String(format: "%.1f → %.1f lb", a, b))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
            } else {
                Text("Not enough weigh-ins this week for a trend. Step on the scale each morning.")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            }
            HealthTrendChart(series: model.weightTrend, tint: Neka.green)
                .frame(height: 140)
        }
        .padding(16)
        .nekaCard(wash: .mint)
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tiles(_ s: WeeklyReview.Summary) -> some View {
        let t = model.targets
        HealthTile(title: "Calories", value: number(s.avgCalories), unit: "calories avg",
                   status: "\(s.calorieDays)/7 in budget", statusColor: hitColor(s.calorieDays),
                   footnote: "budget \(Int(t.calories).formatted())", wash: .peach) {
            HealthMiniBars(values: s.days.map { $0.caloriesIn ?? 0 }, tint: Neka.orange, target: t.calories)
        }
        HealthTile(title: "Protein", value: number(s.avgProtein), unit: "g avg",
                   status: "\(s.proteinDays)/7 on target", statusColor: hitColor(s.proteinDays),
                   footnote: "goal \(Int(t.protein)) g", wash: .mint) {
            HealthMiniBars(values: s.days.map { $0.proteinGrams ?? 0 }, tint: Neka.green, target: t.protein)
        }
        HealthTile(title: "Water", value: number(s.avgWater), unit: "oz avg",
                   status: "\(s.waterDays)/7 on target", statusColor: hitColor(s.waterDays),
                   footnote: "goal \(Int(t.waterOz)) oz", wash: .sky) {
            HealthMiniBars(values: s.days.map { $0.waterOz ?? 0 }, tint: Neka.sky, target: t.waterOz)
        }
        HealthTile(title: "Steps", value: number(s.avgSteps), unit: "avg",
                   status: "\(s.stepDays)/7 on target", statusColor: hitColor(s.stepDays),
                   footnote: "goal \(t.steps.formatted())") {
            HealthMiniBars(values: s.days.map { Double($0.steps ?? 0) }, tint: Neka.ink, target: Double(t.steps))
        }
        HealthTile(title: "Sleep", value: s.avgSleep.map { String(format: "%.1f", $0) } ?? "--", unit: "h avg",
                   status: s.avgSleep == nil ? "No sleep data" : "\(s.sleepDays)/7 nights 7h+",
                   statusColor: s.avgSleep == nil ? Neka.inkTertiary : hitColor(s.sleepDays),
                   wash: .lavender) {
            HealthMiniBars(values: s.days.map { $0.sleepHours ?? 0 }, tint: Neka.lavender, target: t.sleepHours)
        }
        HealthTile(title: "Habits", value: "\(s.workoutsDone)", unit: s.workoutsDone == 1 ? "workout" : "workouts",
                   status: "\(s.weighInDays)/7 weigh-ins", statusColor: hitColor(s.weighInDays),
                   wash: .rose) {
            habitDots(s)
        }
    }

    /// One dot per day: filled = workout done, ring = weighed in.
    private func habitDots(_ s: WeeklyReview.Summary) -> some View {
        let days = WeeklyReview.days(from: s.start, to: s.end, calendar: calendar)
        return HStack(spacing: 4) {
            ForEach(days, id: \.self) { d in
                let day = s.days.first { calendar.isDate($0.date, inSameDayAs: d) }
                VStack(spacing: 4) {
                    Circle()
                        .fill(day?.workoutDone == true ? Neka.rose : Neka.track)
                        .overlay(Circle().stroke(day?.weighedIn == true ? Neka.green : Color.clear, lineWidth: 2))
                        .frame(width: 16, height: 16)
                    Text(d.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Neka.inkTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func number(_ value: Double?) -> String {
        value.map { Int($0.rounded()).formatted() } ?? "--"
    }

    private func hitColor(_ hits: Int) -> Color {
        switch hits {
        case 5...: return Neka.green
        case 3...4: return Neka.orange
        default:   return Neka.rose
        }
    }

    // MARK: - Day by day

    private func dayByDayCard(_ s: WeeklyReview.Summary) -> some View {
        let best = s.best
        let worst = s.worst
        let domainEnd = calendar.date(byAdding: .day, value: 1, to: s.end) ?? s.end
        return VStack(alignment: .leading, spacing: 14) {
            HealthCardHeader(title: "Day by day", trailing: "day score, 0–100")
            Chart(s.scores, id: \.date) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Score", d.score))
                    .foregroundStyle(barColor(d, best: best, worst: worst))
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        Text("\(d.score)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Neka.inkSecondary)
                    }
            }
            .chartXScale(domain: s.start...domainEnd)
            .chartYScale(domain: 0...110)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .frame(height: 150)

            if let best {
                dayRow(title: "Best day", score: best, icon: "star.fill", tint: Neka.green, fill: Neka.greenSoft, summary: s)
            }
            if let worst, worst.date != best?.date {
                dayRow(title: "Toughest day", score: worst, icon: "arrow.down.right", tint: Neka.rose, fill: Neka.roseSoft, summary: s)
            }
            Text("Day score = Home's mood score at end of day: water, steps, protein (20 each), calorie budget and sleep (15), weigh-in (10).")
                .font(.system(size: 10))
                .foregroundColor(Neka.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .nekaCard()
    }

    private func barColor(_ d: WeeklyReview.DayScore, best: WeeklyReview.DayScore?, worst: WeeklyReview.DayScore?) -> Color {
        if d.date == best?.date { return Neka.green }
        if d.date == worst?.date { return Neka.rose }
        return Neka.ink.opacity(0.18)
    }

    private func dayRow(title: String, score: WeeklyReview.DayScore, icon: String, tint: Color, fill: Color, summary: WeeklyReview.Summary) -> some View {
        let day = summary.days.first { calendar.isDate($0.date, inSameDayAs: score.date) }
        let weakest = day.flatMap { WeeklyReview.weakest($0, targets: model.targets, calendar: calendar) }
        return HStack(spacing: 12) {
            NekaIconBadge(systemName: icon, tint: tint, fill: fill)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) · \(score.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(weakest.map { "Held back most by \($0.lowercased())" } ?? "Every box ticked")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
            Spacer()
            Text("\(score.score)")
                .font(Neka.display(22, weight: .semibold))
                .foregroundColor(tint)
        }
    }

    // MARK: - Goal

    @ViewBuilder
    private func goalCard(_ s: WeeklyReview.Summary) -> some View {
        if let goal = model.goal, goal.date > Date() {
            let daysAway = goal.daysAway()
            VStack(alignment: .leading, spacing: 10) {
                HealthCardHeader(title: goal.name, trailing: "\(daysAway) day\(daysAway == 1 ? "" : "s") away")
                if let p = model.projection {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", p.weight))
                            .font(Neka.display(30, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text("lb projected on \(goal.date.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Text(String(format: "Trend: %.1f lb/week over your last %ld weigh-in days.", p.weeklyRate, p.basedOnDays))
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
                if let latest = model.latestWeight, let target = model.goalWeight, latest > target {
                    let weeks = max(1, Double(daysAway) / 7)
                    let needed = (latest - target) / weeks
                    let onPace = model.projection.map { $0.weight <= target } ?? false
                    HStack(spacing: 8) {
                        NekaPill(text: onPace ? "On pace" : String(format: "Need %.1f lb/wk", needed),
                                 tint: onPace ? Neka.green : Neka.orange,
                                 fill: onPace ? Neka.greenSoft : Neka.orangeSoft)
                        Text(String(format: "%.1f lb to %.0f lb", latest - target, target))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
                if s.workoutsDone > 0 {
                    Text("\(s.workoutsDone) workout\(s.workoutsDone == 1 ? "" : "s") done this week.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nekaCard(wash: .sky)
        }
    }

    // MARK: - Empty & reminder

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Neka.inkTertiary)
            Text("Nothing logged this week")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text("Once water, food, steps or weigh-ins land for these days, your review fills in here.")
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard()
    }

    private var reminderPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                NekaIconBadge(systemName: "bell.badge.fill", tint: Neka.lavender, fill: Neka.lavenderSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get this every Sunday")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(permissionDenied
                         ? "Notifications are off for Dialed — turn them on in Settings."
                         : "A reminder at 6 PM to look back and plan the week.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            Button(permissionDenied ? "Open Settings" : "Remind me Sundays at 6 PM") {
                if permissionDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } else {
                    enableSundayReminder()
                }
            }
            .buttonStyle(.nekaPrimary)
        }
        .padding(16)
        .nekaCard()
    }

    private func enableSundayReminder() {
        Task {
            guard await SmartReminders.requestPermission() else {
                permissionDenied = true
                return
            }
            var settings = ReminderSettings.load()
            if !settings.enabled {
                // Asked for the Sunday review only — leave daily nudges off.
                settings.enabled = true
                settings.disabledKinds = Set(ReminderKind.allCases).subtracting([.weeklyReview])
            }
            settings.disabledKinds.remove(.weeklyReview)
            settings.save()
            withAnimation { sundayReminderOn = true }
            await SmartReminders.refresh(context: modelContext)
        }
    }
}

// MARK: - Home card

/// "Your week in review" — shown on Home on Sundays and Mondays.
struct HomeWeeklyReviewCard: View {
    var onOpen: () -> Void

    static func isShowing(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        return weekday == 1 || weekday == 2
    }

    var body: some View {
        let range = WeeklyReview.weekRange(now: Date())
        return Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Neka.lavender)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Neka.lavenderSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR WEEK IN REVIEW")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Text(WeeklyReviewModel.title(range.start, range.end))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("Best day, averages and one thing to fix")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(14)
            .nekaCard(wash: .lavender)
        }
        .buttonStyle(.dialedScale)
    }
}

#Preview {
    NavigationStack {
        WeeklyReviewView()
    }
    .modelContainer(for: DialedSchema.allModels, inMemory: true)
}
