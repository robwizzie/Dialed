//
//  LogIntents.swift
//  Dialed
//
//  More Siri and Shortcuts, said the way you'd text it:
//    "Log food in Dialed" → "A protein shake"
//    "Log exercise in Dialed" → "Bench 185 for 8"
//    "Log my weight in Dialed" → "206.5"
//    "How many calories do I have left in Dialed"
//  Food resolves through your favorites and recent foods first, then the
//  food table, then Apple Intelligence. Sets land on today's workout log
//  exactly as if you'd typed them in the logger.
//

import AppIntents
import SwiftData

// MARK: - Log food

struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log food"
    static let description = IntentDescription("Logs what you ate in Dialed: a favorite, something recent, or a description.")
    static let openAppWhenRun = false

    @Parameter(title: "Food", requestValueDialog: IntentDialog("What did you eat?"))
    var food: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$food)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "Tell me what you ate, like \"a protein shake\"."))
        }
        let context = try IntentStore.context()
        guard var draft = await Self.draft(for: text, context: context) else {
            return .result(dialog: IntentDialog(stringLiteral: "I couldn't work out \"\(text)\". Try adding it in Dialed."))
        }
        draft.time = Date()
        QuickLogService.logMeal(draft, context: context)
        await IntentStore.finish(context)

        let totals = QuickLogService.todayTotals(context: context)
        let earned = await EarnedCalories.day(context: context).earned
        let left = totals.calorieTarget + earned - totals.calories
        let leftText = left >= 0 ? "\(Int(left.rounded()).formatted()) left today" : "\(Int((-left).rounded()).formatted()) over today"
        let message = "Logged \(draft.name.lowercased()), \(Int(draft.calories.rounded())) calories, "
            + "\(Int(draft.protein.rounded())) g protein. \(leftText)."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    /// Favorite → recent → food table → Apple Intelligence.
    @MainActor
    static func draft(for text: String, context: ModelContext) async -> FoodDraft? {
        let query = strip(text)
        if let fav = QuickLogService.favorite(named: query) { return FoodDraft(fav) }
        let recents = FoodLog.recents(context: context, limit: 40)
        if let recent = recents.first(where: { $0.name.lowercased() == query })
            ?? recents.first(where: { !$0.name.isEmpty && $0.name.lowercased().contains(query) }) {
            return recent
        }
        let table = MealMath.estimate(text)
        if table.isComplete {
            var d = FoodDraft()
            d.name = query.prefix(1).uppercased() + query.dropFirst()
            d.calories = table.parts.reduce(0) { $0 + $1.calories }.rounded()
            d.protein = table.parts.reduce(0) { $0 + $1.protein }.rounded()
            d.carbs = table.parts.reduce(0) { $0 + $1.carbs }.rounded()
            d.fat = table.parts.reduce(0) { $0 + $1.fat }.rounded()
            return d
        }
        if let ai = await DialedAI.estimateMeal(text) {
            var d = FoodDraft()
            d.name = ai.name.isEmpty ? String(query) : ai.name
            d.calories = Double(ai.calories)
            d.protein = Double(ai.proteinGrams)
            d.carbs = ai.carbsGrams.map(Double.init)
            d.fat = ai.fatGrams.map(Double.init)
            return d
        }
        return nil
    }

    /// "a protein shake" → "protein shake"
    private static func strip(_ text: String) -> String {
        var s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for lead in ["a ", "an ", "my ", "some ", "the "] where s.hasPrefix(lead) {
            s = String(s.dropFirst(lead.count))
        }
        return s
    }
}

// MARK: - Log exercise

struct LogExerciseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log exercise"
    static let description = IntentDescription("Adds sets to today's workout in Dialed, like \"bench 185 for 8\".")
    static let openAppWhenRun = false

    @Parameter(title: "What you did", requestValueDialog: IntentDialog("What did you do? Like \"bench 185 for 8\"."))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$text)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentStore.context()
        let known = PlanWorkoutLogStore.knownExercises(context: context)
        var exercises = WorkoutNarrative.read(text, known: known).exercises
        if exercises.isEmpty {
            exercises = WorkoutTextParser.parse(text, known: known).filter { !$0.sets.isEmpty }
        }
        guard !exercises.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "I couldn't read that. Try \"bench 185 for 8\"."))
        }
        Self.append(exercises, context: context)
        await IntentStore.finish(context)
        return .result(dialog: IntentDialog(stringLiteral: "Added \(Self.describe(exercises)) to today's workout."))
    }

    /// Finished sets onto today's log (made if needed), after any already there.
    @MainActor
    static func append(_ exercises: [WorkoutTextParser.ParsedExercise], context: ModelContext, now: Date = Date()) {
        let day = Calendar.current.startOfDay(for: now)
        let key = WorkoutPlanStore.key(day)
        let log: PlanWorkoutLog
        if let existing = PlanWorkoutLogStore.log(for: key, context: context) {
            log = existing
        } else {
            let session = WorkoutPlanStore.session(on: day)
            log = PlanWorkoutLog(dayKey: key, date: day, title: session.title, kindRaw: session.kind.rawValue)
            context.insert(log)
        }
        let existing = PlanWorkoutLogStore.sets(for: log.id, context: context)
        var nextOrder = (existing.map(\.exerciseOrder).max() ?? -1) + 1
        for ex in exercises {
            let mine = existing.filter { $0.exerciseName == ex.name }
            let order: Int
            if let o = mine.first?.exerciseOrder { order = o } else { order = nextOrder; nextOrder += 1 }
            var index = (mine.map(\.setIndex).max() ?? -1) + 1
            for s in ex.sets {
                context.insert(PlanSetLog(workoutID: log.id, date: day, exerciseName: ex.name, exerciseOrder: order,
                                          setIndex: index, weightLbs: s.weight ?? 0, reps: s.reps,
                                          targetReps: nil, completed: true))
                index += 1
            }
        }
        log.savedAt = now
        try? context.save()
        PlanWorkoutLogStore.remember(exercises.map(\.name))
        PlanWorkoutLogStore.setDone(key, true)
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    /// "Bench press 185 × 8" · "Bench press 3 × 185 × 8" · "Bench press and Pec deck fly"
    static func describe(_ exercises: [WorkoutTextParser.ParsedExercise]) -> String {
        guard exercises.count == 1, let ex = exercises.first else {
            return exercises.map(\.name).joined(separator: " and ")
        }
        let sets = ex.sets
        guard let first = sets.first else { return ex.name }
        let one = (first.weight.map { "\(formatPounds($0)) × " } ?? "") + "\(first.reps)"
        if sets.allSatisfy({ $0 == first }) {
            return sets.count == 1 ? "\(ex.name) \(one)" : "\(ex.name) \(sets.count) × \(one)"
        }
        return "\(ex.name), \(sets.count) sets"
    }
}

// MARK: - Log weight

struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log weight"
    static let description = IntentDescription("Records a weigh-in in Dialed.")
    static let openAppWhenRun = false

    @Parameter(title: "Pounds", requestValueDialog: IntentDialog("What did you weigh?"))
    var pounds: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$pounds) lb")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (60...700).contains(pounds) else {
            return .result(dialog: IntentDialog(stringLiteral: "That doesn't look like a weight. Try again in pounds."))
        }
        let context = try IntentStore.context()
        context.insert(WeightEntry(pounds: pounds))
        try? context.save()
        // Same as the weigh-in sheet: keep the profile's weight fresh.
        var settings = UserSettings.load()
        settings.currentWeight = pounds
        settings.save()
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
        await IntentStore.finish(context)
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(formatPounds(pounds)) lb."))
    }
}

// MARK: - Calories left

struct CaloriesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories left today"
    static let description = IntentDescription("How many calories you have left today, including what exercise earned back.")
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let context = try IntentStore.context()
        let totals = await QuickLogService.todayTotalsIncludingHealth(context: context)
        let earned = await EarnedCalories.day(context: context).earned
        let left = (totals.calorieTarget + earned - totals.calories).rounded()
        var message = left >= 0
            ? "\(Int(left).formatted()) calories left today"
            : "\(Int(-left).formatted()) calories over today"
        if earned > 0 { message += ", including \(Int(earned).formatted()) you earned exercising" }
        message += ". \(Int(totals.protein.rounded())) of \(Int(totals.proteinTarget)) g protein."
        return .result(value: Int(left), dialog: IntentDialog(stringLiteral: message))
    }
}
