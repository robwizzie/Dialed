//
//  WeeklyReviewModel.swift
//  Dialed
//
//  Loads a Monday–Sunday week for the weekly review from Apple Health
//  (WaterH water, steps, food apps), the Pixel Watch sleep synced into
//  SwiftData, what you log in Dialed, and your scale. The math lives in
//  WeeklyReview (pure, tested); the "one thing to fix" asks Apple
//  Intelligence and falls back to WeeklyReview.biggestGap.
//

import Foundation
import SwiftUI
import SwiftData
import HealthKit
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class WeeklyReviewModel: ObservableObject {
    static let maxWeeksBack = 8

    @Published var weeksBack = 0
    @Published private(set) var isLoading = false
    @Published private(set) var summary: WeeklyReview.Summary?
    @Published private(set) var targets = WeeklyReview.Targets(calories: 2_200, protein: 190, waterOz: 120)
    @Published private(set) var fix: WeeklyReview.Fix?
    @Published private(set) var fixIsAI = false
    @Published private(set) var isThinking = false
    @Published private(set) var weightTrend: [HealthInsights.DayValue] = []
    @Published private(set) var goal: GoalEvent?
    @Published private(set) var projection: WeightChallengeEngine.Projection?
    @Published private(set) var latestWeight: Double?
    @Published private(set) var goalWeight: Double?

    private let health = HealthKitManager.shared
    private let calendar = Calendar.current
    /// Apple Intelligence answers, per week, so flipping weeks doesn't re-ask.
    private var aiFixes: [Date: WeeklyReview.Fix] = [:]

    var range: (start: Date, end: Date) {
        WeeklyReview.weekRange(now: Date(), weeksBack: weeksBack, calendar: calendar)
    }

    var rangeTitle: String { Self.title(range.start, range.end) }

    /// "Oct 12 – 18" / "Sep 28 – Oct 4".
    nonisolated static func title(_ startDate: Date, _ endDate: Date, calendar: Calendar = .current) -> String {
        let sameMonth = calendar.component(.month, from: startDate) == calendar.component(.month, from: endDate)
        let start = startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = sameMonth ? endDate.formatted(.dateTime.day()) : endDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    func shift(_ delta: Int) {
        weeksBack = max(0, min(Self.maxWeeksBack, weeksBack + delta))
    }

    // MARK: - Load

    func load(context: ModelContext) async {
        isLoading = true
        defer { isLoading = false }

        let now = Date()
        let today = calendar.startOfDay(for: now)
        let (start, end) = range
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        let span = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        let settings = UserSettings.load()

        // Apple Health, in parallel (fetchDailySums counts back from today).
        async let hkWater = try? health.fetchDailySums(.dietaryWater, unit: .fluidOunceUS(), days: span)
        async let hkSteps = try? health.fetchDailySums(.stepCount, unit: .count(), days: span)
        async let hkProtein = try? health.fetchDailySums(.dietaryProtein, unit: .gram(), days: span)
        async let hkEnergy = try? health.fetchDailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: span)
        let readingsStart = calendar.date(byAdding: .day, value: -35, to: start) ?? start
        let readings = await WeightDataSource.readings(context: context, since: readingsStart)
        let waterByDay = await hkWater ?? [:]
        let stepsByDay = await hkSteps ?? [:]
        let proteinByDay = await hkProtein ?? [:]
        let energyByDay = await hkEnergy ?? [:]

        // Local data.
        let logs = (try? context.fetch(FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date >= start && $0.date < endExclusive }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < endExclusive }))) ?? []
        let sleeps = (try? context.fetch(FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.logicalDate >= start && $0.logicalDate < endExclusive }))) ?? []
        let workouts = WeeklyReview.workoutKeys(UserDefaults.standard.string(forKey: "workout.doneDays") ?? "")

        let mealKind = ContextEvent.Kind.meal.rawValue
        let waterKind = ContextEvent.Kind.water.rawValue
        let weighInDays = Set(readings.map { calendar.startOfDay(for: $0.date) })

        let days: [WeeklyReview.Day] = WeeklyReview.days(from: start, to: min(end, today), calendar: calendar).map { d in
            let log = logs.first { calendar.isDate($0.date, inSameDayAs: d) }
            let dayEvents = events.filter { calendar.isDate($0.logicalDate, inSameDayAs: d) }
            let meals = dayEvents.filter { $0.kindRaw == mealKind }
            let captured = dayEvents.filter { $0.kindRaw == waterKind }.reduce(0) { $0 + ($1.value ?? 0) }
            let calories = max((log?.caloriesConsumed ?? 0) + meals.reduce(0) { $0 + ($1.value ?? 0) }, energyByDay[d] ?? 0)
            let protein = max((log?.proteinGrams ?? 0) + meals.reduce(0) { $0 + ($1.secondaryValue ?? 0) }, proteinByDay[d] ?? 0)
            let water = max(waterByDay[d] ?? 0, log?.waterOz ?? 0) + captured
            let steps = Int(max(stepsByDay[d] ?? 0, Double(log?.steps ?? 0)))
            let night = sleeps.filter { calendar.isDate($0.logicalDate, inSameDayAs: d) }.map(\.asleepMinutes).max()
            let sleepMinutes = night ?? log?.sleepDurationMinutes
            return WeeklyReview.Day(
                date: d,
                caloriesIn: calories > 0 ? calories : nil,
                proteinGrams: protein > 0 ? protein : nil,
                waterOz: water > 0 ? water : nil,
                steps: steps > 0 ? steps : nil,
                sleepHours: sleepMinutes.flatMap { $0 > 0 ? Double($0) / 60 : nil },
                weighedIn: weighInDays.contains(d),
                workoutDone: workouts.contains(WeeklyReview.dayKey(d, calendar: calendar))
            )
        }

        let latest = readings.last?.pounds ?? settings.currentWeight
        let targets = WeeklyReview.Targets(
            calories: settings.calorieTarget ?? HomeViewModel.estimatedCutCalories(weight: latest),
            protein: settings.proteinTargetGrams,
            waterOz: settings.waterTargetOz
        )
        let summary = WeeklyReview.summarize(days: days, readings: readings, targets: targets,
                                             start: start, end: end, calendar: calendar)

        self.targets = targets
        self.summary = summary
        latestWeight = readings.last?.pounds
        goalWeight = settings.goalWeight > 0 ? settings.goalWeight : nil
        weightTrend = WeightChallengeEngine.dailySeries(readings, calendar: calendar)
            .filter { $0.day >= start && $0.day <= end }
            .map { HealthInsights.DayValue(date: $0.day, value: $0.trend) }
        goal = GoalEvent.load()
        if let goal, goal.date > now {
            projection = WeightChallengeEngine.projection(readings: readings, to: goal.date, now: now)
        } else {
            projection = nil
        }

        let fallback = WeeklyReview.biggestGap(summary, targets: targets)
        if let cached = aiFixes[start] {
            fix = cached
            fixIsAI = true
            return
        }
        fix = fallback
        fixIsAI = false
        guard DialedAI.isAvailable, !summary.days.isEmpty else { return }

        isThinking = true
        defer { isThinking = false }
        let prompt = WeeklyReview.promptText(summary, targets: targets,
                                             goalName: goal?.name, daysToGoal: goal?.daysAway(from: now))
        let weeksBackAtStart = weeksBack
        if let ai = await DialedAI.weeklyFix(summary: prompt, suggestion: fallback), weeksBack == weeksBackAtStart {
            aiFixes[start] = ai
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                fix = ai
                fixIsAI = true
            }
        }
    }
}

// MARK: - Apple Intelligence

extension DialedAI {
    /// "One thing to fix next week", from the week's numbers. nil when
    /// Apple Intelligence isn't available — callers keep the deterministic
    /// suggestion.
    static func weeklyFix(summary: String, suggestion: WeeklyReview.Fix) async -> WeeklyReview.Fix? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: coachRules)
            let areas = WeeklyReview.FixArea.allCases.map(\.rawValue).joined(separator: ", ")
            let prompt = """
            Here is the user's past week. Pick the ONE habit that would help them most next week \
            and say exactly what to do, using their numbers. A simple rule suggests: \
            "\(suggestion.headline) — \(suggestion.detail)" Agree with it unless the numbers clearly point elsewhere. \
            The area must be one of: \(areas).

            \(summary)
            """
            do {
                let response = try await session.respond(to: prompt, generating: GeneratedWeeklyFix.self)
                let g = response.content
                let picked = g.area.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let area = WeeklyReview.FixArea.allCases.first { $0.rawValue.lowercased() == picked } ?? suggestion.area
                let headline = g.headline.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = g.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !headline.isEmpty, !detail.isEmpty else { return nil }
                return WeeklyReview.Fix(area: area, headline: headline, detail: detail)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedWeeklyFix {
    @Guide(description: "One of: logging, calories, protein, water, steps, sleep, weighIn, none")
    var area: String

    @Guide(description: "The fix as a short imperative headline, 3 to 6 words")
    var headline: String

    @Guide(description: "Two short sentences: the number that shows the gap, then one concrete daily action")
    var detail: String
}
#endif
