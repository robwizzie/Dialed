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
