//
//  WidgetIntents.swift
//  DialedWidgets
//
//  What the widget's buttons run. The extension can't open the app's
//  SwiftData store, so a tap only queues the log in the App Group
//  (Shared/WidgetBridge.swift) and redraws; the widget counts it right
//  away and the app logs it for real the next time it comes forward.
//

import AppIntents
import WidgetKit

struct AddWaterWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Add water"
    static let isDiscoverable = false

    @Parameter(title: "Ounces")
    var ounces: Double

    init() {}

    init(ounces: Double) {
        self.ounces = ounces
    }

    func perform() async throws -> some IntentResult {
        WidgetBridge().enqueue(.water(ounces))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Water widget settings

enum WaterPreset: String, AppEnum {
    case sips, glasses, bottles

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pour sizes"
    static let caseDisplayRepresentations: [WaterPreset: DisplayRepresentation] = [
        .sips: "Sips · 4, 8, 12 oz",
        .glasses: "Glasses · 8, 16, 24 oz",
        .bottles: "Bottles · 16, 24, 32 oz"
    ]

    /// Ounces on the widget's buttons, smallest first.
    var amounts: [Double] {
        switch self {
        case .sips:    return [4, 8, 12]
        case .glasses: return [8, 16, 24]
        case .bottles: return [16, 24, 32]
        }
    }
}

struct WaterWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Water"
    static let description = IntentDescription("Choose the pour sizes on the buttons.")

    @Parameter(title: "Pour sizes", default: .glasses)
    var pours: WaterPreset

    init() {}
}

// MARK: - Favorites

struct LogFavoriteWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log favorite meal"
    static let isDiscoverable = false

    /// SavedMeal id, as a UUID string.
    @Parameter(title: "Favorite")
    var favoriteID: String

    init() {}

    init(favoriteID: UUID) {
        self.favoriteID = favoriteID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: favoriteID) {
            WidgetBridge().enqueue(.favorite(id))
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}
