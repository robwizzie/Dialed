//
//  WidgetSync.swift
//  Dialed
//
//  App side of the widget handshake (Shared/WidgetBridge.swift). Whenever
//  the app comes forward or data changes it: logs the widget taps waiting
//  in the shared queue through QuickLogService, writes a fresh snapshot of
//  today, and asks WidgetKit to redraw. Without the App Group (not yet
//  provisioned) the bridge is a no-op and this quietly does nothing.
//

import SwiftUI
import SwiftData
import WidgetKit

@MainActor
enum WidgetSync {
    private static var isRunning = false
    private static var runAgain = false

    static func refresh(context: ModelContext) async {
        // Logging below posts dialedDataDidChange, which calls back in here;
        // coalesce those into one extra pass instead of overlapping runs.
        guard !isRunning else {
            runAgain = true
            return
        }
        isRunning = true
        defer { isRunning = false }

        repeat {
            runAgain = false
            await runOnce(context: context)
        } while runAgain
    }

    private static func runOnce(context: ModelContext) async {
        let bridge = WidgetBridge()

        // (a) Widget taps → real logs (saved, mirrored to Health).
        for log in bridge.drain() {
            switch log.kind {
            case .water:
                if let oz = log.amount, oz > 0 {
                    QuickLogService.logWater(oz, at: log.date, context: context)
                }
            case .favorite:
                if let id = log.favoriteID, let meal = QuickLogService.favorite(id: id) {
                    QuickLogService.logFavorite(meal, at: log.date, context: context)
                }
            }
        }

        // (b) Fresh snapshot for the widget.
        if bridge.isAvailable {
            let totals = await QuickLogService.todayTotalsIncludingHealth(context: context)
            bridge.writeSnapshot(snapshot(from: totals, meals: todayMeals(context: context)))
        }

        // (c) Redraw, and keep Siri's "Log <favorite>" phrases current.
        WidgetCenter.shared.reloadAllTimelines()
        DialedShortcuts.updateAppShortcutParameters()
    }

    static func snapshot(from totals: QuickLogService.Totals, meals: [WidgetMeal] = [], now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            waterOz: totals.waterOz,
            waterTargetOz: totals.waterTargetOz,
            protein: totals.protein,
            proteinTarget: totals.proteinTarget,
            calories: totals.calories,
            calorieTarget: totals.calorieTarget,
            favorites: QuickLogService.favorites().prefix(4).map {
                WidgetFavorite(id: $0.id, name: $0.name, calories: $0.calories, protein: $0.proteinGrams)
            },
            updatedAt: now,
            meals: meals
        )
    }

    /// Meals logged in Dialed today, oldest first.
    private static func todayMeals(context: ModelContext, now: Date = Date()) -> [WidgetMeal] {
        let logical = Calendar.current.logicalStartOfDay(for: now)
        let meal = ContextEvent.Kind.meal.rawValue
        let events = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate == logical && $0.kindRaw == meal },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        return events.map {
            WidgetMeal(name: $0.mealName, calories: $0.value ?? 0, protein: $0.secondaryValue ?? 0, time: $0.timestamp)
        }
    }

    // MARK: - Insights

    /// Home's latest read of the day (activity, recovery, weight, score,
    /// challenge) plus today's mood avatar → the data widgets.
    static func publish(_ home: HomeViewModel, avatar: UIImage?, now: Date = Date()) {
        let bridge = WidgetBridge()
        guard bridge.isAvailable else { return }
        bridge.writeInsights(insights(from: home, now: now))
        WidgetBridge.writeAvatar(avatar.flatMap(thumbnail))
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func insights(from home: HomeViewModel, now: Date = Date()) -> WidgetInsights {
        let score = home.moodReading.map { reading in
            WidgetInsights.Score(
                value: reading.score,
                mood: reading.mood.rawValue,
                title: reading.mood.title,
                emoji: reading.mood.emoji,
                tagline: reading.mood.tagline,
                accentHex: reading.mood.accentHex,
                parts: reading.components.map { .init(name: $0.name, points: $0.points, maxPoints: $0.maxPoints) },
                boost: reading.boosts.first?.action
            )
        }

        var challenge: WidgetInsights.Challenge?
        if let c = home.challenge, let p = home.progress {
            let percent = c.scoring == .percent
            let leader: String
            switch p.leader {
            case .you:     leader = "you"
            case .friend:  leader = "friend"
            case .tied:    leader = "tied"
            case .unknown: leader = "unknown"
            }
            challenge = WidgetInsights.Challenge(
                friendName: c.friendDisplayName,
                scoresPercent: percent,
                youLost: percent ? p.lostPercent : p.lostLbs,
                friendLost: p.friend.map { percent ? $0.lostPercent : $0.lostLbs },
                leader: leader,
                margin: p.margin,
                dayNumber: p.dayNumber,
                totalDays: p.totalDays,
                daysLeft: p.daysLeft,
                goalLossLbs: p.goalLossLbs,
                lostLbs: p.lostLbs,
                weighedInToday: p.weighedInToday,
                weighInStreak: p.weighInStreak,
                neededPace: home.race?.result.needed,
                yourPace: home.race?.result.current,
                raceStatus: home.race.map { r -> String in
                    switch r.result.status {
                    case .ahead:   return "ahead"
                    case .onTrack: return "onTrack"
                    case .behind:  return "behind"
                    case .unknown: return "unknown"
                    }
                }
            )
        }

        let goal = home.goalEvent.flatMap { event in
            event.date > now
                ? WidgetInsights.Goal(name: event.name, date: event.date, projectedWeight: home.goalProjection?.weight)
                : nil
        }

        return WidgetInsights(
            steps: home.steps,
            stepGoal: home.stepGoal,
            stepsWeek: home.stepsSeries,
            waterWeek: home.waterWeek,
            sleepHours: home.sleepHours,
            sleepWeek: home.sleepSeries,
            hrv: home.hrv,
            hrvBaseline: home.hrvBaseline,
            restingHR: home.restingHR,
            weight: home.latestWeight?.pounds,
            weightTrend: WeightChallengeEngine.dailySeries(home.weightReadings).suffix(14).map(\.trend),
            score: score,
            challenge: challenge,
            goal: goal,
            updatedAt: now,
            miles: home.milesToday,
            mileStreak: home.mileStreak
        )
    }

    /// Widgets have a tight memory budget — keep the avatar small.
    private static func thumbnail(_ image: UIImage) -> Data? {
        let side: CGFloat = 360
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - Hook

private struct WidgetSyncModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await WidgetSync.refresh(context: modelContext) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await WidgetSync.refresh(context: modelContext) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
                Task { await WidgetSync.refresh(context: modelContext) }
            }
    }
}

extension View {
    /// Keep the home-screen widget and its tap queue in step with the app.
    func widgetSync() -> some View {
        modifier(WidgetSyncModifier())
    }
}
