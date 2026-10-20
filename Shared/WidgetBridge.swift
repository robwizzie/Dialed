//
//  WidgetBridge.swift
//  Dialed (app + DialedWidgets)
//
//  The handshake between the app and its widgets, through the shared
//  App Group's UserDefaults. The app writes a small snapshot of today
//  (water, protein, calories, favorite meals); the widget only reads it.
//  Widget buttons can't touch the app's SwiftData store, so a tap appends
//  to a pending queue instead — the widget shows it right away on top of
//  the snapshot, and the app logs it properly the next time it runs.
//
//  Foundation only: this file is compiled into both targets.
//

import Foundation

struct WidgetFavorite: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var calories: Double
    var protein: Double
}

struct WidgetSnapshot: Codable, Equatable {
    var waterOz: Double
    var waterTargetOz: Double
    var protein: Double
    var proteinTarget: Double
    var calories: Double
    var calorieTarget: Double
    var favorites: [WidgetFavorite]
    var updatedAt: Date

    var waterProgress: Double { waterTargetOz > 0 ? min(1, waterOz / waterTargetOz) : 0 }
    var proteinLeft: Double { max(0, proteinTarget - protein) }
    var caloriesLeft: Double { calorieTarget - calories }

    /// Shown before the app has written anything (and in the gallery).
    static let placeholder = WidgetSnapshot(
        waterOz: 64, waterTargetOz: 120,
        protein: 110, proteinTarget: 190,
        calories: 1_250, calorieTarget: 2_200,
        favorites: [WidgetFavorite(id: UUID(), name: "Clear Whey Shake", calories: 90, protein: 20)],
        updatedAt: Date()
    )

    /// The numbers to show at `now`: zeroed after the day rolls over (the
    /// app hasn't refreshed yet), plus any widget taps still waiting in the
    /// queue for today.
    func display(with pending: [PendingLog], now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        var out = self
        let today = WidgetBridge.logicalDay(for: now, calendar: calendar)
        if WidgetBridge.logicalDay(for: updatedAt, calendar: calendar) != today {
            out.waterOz = 0
            out.protein = 0
            out.calories = 0
        }
        for log in pending where WidgetBridge.logicalDay(for: log.date, calendar: calendar) == today {
            switch log.kind {
            case .water:
                out.waterOz += log.amount ?? 0
            case .favorite:
                if let meal = favorites.first(where: { $0.id == log.favoriteID }) {
                    out.calories += meal.calories
                    out.protein += meal.protein
                }
            }
        }
        return out
    }
}

/// A widget tap waiting for the app to log it.
struct PendingLog: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case water
        case favorite
    }

    var id: UUID
    var kind: Kind
    /// Ounces, for water.
    var amount: Double?
    /// The saved meal, for favorites.
    var favoriteID: UUID?
    var date: Date

    static func water(_ ounces: Double, at date: Date = Date()) -> PendingLog {
        PendingLog(id: UUID(), kind: .water, amount: ounces, favoriteID: nil, date: date)
    }

    static func favorite(_ id: UUID, at date: Date = Date()) -> PendingLog {
        PendingLog(id: UUID(), kind: .favorite, amount: nil, favoriteID: id, date: date)
    }
}

struct WidgetBridge {
    static let appGroupID = "group.org.robertwiscount.Dialed"
    static let widgetKind = "DialedTodayWidget"
    /// Matches the app's 4 AM day cutoff (Constants.dayCutoffHour).
    static let dayCutoffHour = 4

    static let snapshotKey = "widget.snapshot.v1"
    static let pendingKey = "widget.pending.v1"
    static let processedKey = "widget.processed.v1"
    /// How many drained ids we remember for de-duplication.
    static let processedMemory = 200

    /// Nil when the App Group isn't provisioned; every call is then a no-op.
    let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: WidgetBridge.appGroupID)) {
        self.defaults = defaults
    }

    var isAvailable: Bool { defaults != nil }

    // MARK: - Snapshot

    func readSnapshot() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.snapshotKey) else { return nil }
        return try? Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    func writeSnapshot(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? Self.encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    // MARK: - Pending queue

    func pending() -> [PendingLog] {
        guard let data = defaults?.data(forKey: Self.pendingKey) else { return [] }
        return (try? Self.decoder.decode([PendingLog].self, from: data)) ?? []
    }

    func enqueue(_ log: PendingLog) {
        guard defaults != nil else { return }
        var queue = pending()
        guard !queue.contains(where: { $0.id == log.id }) else { return }
        queue.append(log)
        writePending(queue)
    }

    /// Takes the queued logs the app hasn't handled yet, oldest first, and
    /// removes them from the queue. Ids are remembered so a log that is
    /// re-delivered (e.g. a write that raced the drain) isn't logged twice.
    func drain() -> [PendingLog] {
        guard let defaults else { return [] }
        let queue = pending()
        guard !queue.isEmpty else { return [] }

        var processed = defaults.stringArray(forKey: Self.processedKey) ?? []
        var seen = Set(processed)
        var fresh: [PendingLog] = []
        for log in queue.sorted(by: { $0.date < $1.date }) where !seen.contains(log.id.uuidString) {
            seen.insert(log.id.uuidString)
            fresh.append(log)
            processed.append(log.id.uuidString)
        }
        defaults.set(Array(processed.suffix(Self.processedMemory)), forKey: Self.processedKey)

        // Re-read so a tap that landed meanwhile stays queued.
        let drained = Set(queue.map(\.id))
        writePending(pending().filter { !drained.contains($0.id) })
        return fresh
    }

    private func writePending(_ queue: [PendingLog]) {
        guard let defaults, let data = try? Self.encoder.encode(queue) else { return }
        defaults.set(data, forKey: Self.pendingKey)
    }

    // MARK: - Helpers

    /// Start of the "app day" (before 4 AM counts as the previous day).
    static func logicalDay(for date: Date, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < dayCutoffHour else { return base }
        return calendar.date(byAdding: .day, value: -1, to: base) ?? base
    }

    // Default date strategy (reference-date seconds) round-trips exactly.
    private static var encoder: JSONEncoder { JSONEncoder() }
    private static var decoder: JSONDecoder { JSONDecoder() }
}
