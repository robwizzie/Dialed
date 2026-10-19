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
            bridge.writeSnapshot(snapshot(from: totals))
        }

        // (c) Redraw, and keep Siri's "Log <favorite>" phrases current.
        WidgetCenter.shared.reloadAllTimelines()
        DialedShortcuts.updateAppShortcutParameters()
    }

    static func snapshot(from totals: QuickLogService.Totals, now: Date = Date()) -> WidgetSnapshot {
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
            updatedAt: now
        )
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
