//
//  DialedIntents.swift
//  Dialed
//
//  Siri, Shortcuts and the Action button: log water, log a favorite meal,
//  or hear how today is going — without opening the app. Each intent opens
//  the same SwiftData store the app uses and logs through QuickLogService,
//  so Apple Health write-back and the widget refresh happen as usual.
//

import AppIntents
import SwiftData

// MARK: - Store

/// One container for intents, created on first use. With no explicit
/// configuration it opens the app's default store.
@MainActor
enum IntentStore {
    private static var container: ModelContainer?

    static func context() throws -> ModelContext {
        if let container { return container.mainContext }
        let made = try ModelContainer(for: Schema(DialedSchema.allModels))
        container = made
        return made.mainContext
    }

    /// After a log (or before reading totals): log queued widget taps,
    /// refresh the widget snapshot and Siri's favorite-meal phrases.
    static func finish(_ context: ModelContext) async {
        await WidgetSync.refresh(context: context)
    }
}

// MARK: - Log water

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"
    static let description = IntentDescription("Adds water to today's total in Dialed.")
    static let openAppWhenRun = false

    @Parameter(title: "Ounces", default: 16)
    var ounces: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$ounces) oz of water")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let oz = Double(min(max(ounces, 1), 128))
        let context = try IntentStore.context()
        QuickLogService.logWater(oz, context: context)
        await IntentStore.finish(context)
        let totals = QuickLogService.todayTotals(context: context)
        let message = "Logged \(Int(oz)) oz. You're at \(Int(totals.waterOz.rounded())) of \(Int(totals.waterTargetOz)) oz today."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Favorite meals

struct SavedMealEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Favorite meal"
    static let defaultQuery = SavedMealQuery()

    var id: UUID
    var name: String
    var calories: Double
    var protein: Double

    init(_ meal: SavedMeal) {
        id = meal.id
        name = meal.name
        calories = meal.calories
        protein = meal.proteinGrams
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(Int(calories)) calories · \(Int(protein)) g protein"
        )
    }
}

struct SavedMealQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [UUID]) async throws -> [SavedMealEntity] {
        SavedMealsManager.load().filter { identifiers.contains($0.id) }.map(SavedMealEntity.init)
    }

    func entities(matching string: String) async throws -> [SavedMealEntity] {
        let query = string.lowercased()
        return SavedMealsManager.load()
            .filter { $0.name.lowercased().contains(query) }
            .map(SavedMealEntity.init)
    }

    func suggestedEntities() async throws -> [SavedMealEntity] {
        SavedMealsManager.load().map(SavedMealEntity.init)
    }
}

struct LogFavoriteMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log favorite meal"
    static let description = IntentDescription("Logs one of your Dialed favorites now.")
    static let openAppWhenRun = false

    @Parameter(title: "Meal")
    var meal: SavedMealEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$meal)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let saved = QuickLogService.favorite(id: meal.id) ?? QuickLogService.favorite(named: meal.name) else {
            return .result(dialog: IntentDialog(stringLiteral: "I couldn't find that favorite in Dialed."))
        }
        let context = try IntentStore.context()
        QuickLogService.logFavorite(saved, context: context)
        await IntentStore.finish(context)
        let totals = QuickLogService.todayTotals(context: context)
        let message = "Logged \(saved.name). \(totals.spokenSummary)."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Today status

struct TodayStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "How am I doing today"
    static let description = IntentDescription("Water, protein and calories left today, from Dialed.")
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = try IntentStore.context()
        await IntentStore.finish(context)
        let totals = await QuickLogService.todayTotalsIncludingHealth(context: context)
        let summary = totals.spokenSummary
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary + "."))
    }
}

// MARK: - Siri phrases

struct DialedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Add water in \(.applicationName)",
                "Log a drink in \(.applicationName)"
            ],
            shortTitle: "Log water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogFavoriteMealIntent(),
            phrases: [
                "Log \(\.$meal) in \(.applicationName)",
                "Log a favorite meal in \(.applicationName)"
            ],
            shortTitle: "Log favorite",
            systemImageName: "star.fill"
        )
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Log a meal in \(.applicationName)",
                "Log what I ate in \(.applicationName)"
            ],
            shortTitle: "Log food",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogExerciseIntent(),
            phrases: [
                "Log exercise in \(.applicationName)",
                "Log a set in \(.applicationName)",
                "Log my lift in \(.applicationName)"
            ],
            shortTitle: "Log exercise",
            systemImageName: "dumbbell.fill"
        )
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Log my weight in \(.applicationName)",
                "Log a weigh-in in \(.applicationName)"
            ],
            shortTitle: "Log weight",
            systemImageName: "scalemass.fill"
        )
        AppShortcut(
            intent: CaloriesLeftIntent(),
            phrases: [
                "How many calories do I have left in \(.applicationName)",
                "Calories left in \(.applicationName)"
            ],
            shortTitle: "Calories left",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: TodayStatusIntent(),
            phrases: [
                "How am I doing in \(.applicationName)",
                "What's left today in \(.applicationName)"
            ],
            shortTitle: "Today's status",
            systemImageName: "chart.bar.fill"
        )
    }
}
