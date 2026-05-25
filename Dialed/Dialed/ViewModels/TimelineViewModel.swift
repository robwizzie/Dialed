//
//  TimelineViewModel.swift
//  Dialed
//
//  Backs the Timeline view. Owns the selected day + groups ContextEvents
//  into per-hour buckets so the view doesn't need to know about Calendar
//  arithmetic. Kept tiny on purpose — Timeline is read-only, so the view
//  model is mostly a lens over a SwiftData query.
//

import Foundation
import SwiftData

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published private(set) var events: [ContextEvent] = []

    /// 7 days back, today, 1 day forward — gives the user a finger-strip to
    /// scrub recent context without endless scroll. Today is always present
    /// and pinned regardless of where the strip lands.
    var dayStrip: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-7...1).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: today)
        }
    }

    /// Events for `selectedDate`, sorted ascending by timestamp.
    var orderedEvents: [ContextEvent] { events }

    /// Events grouped by clock hour (0–23) for sectioning. Buckets without
    /// events are omitted. Order preserved.
    var groupedByHour: [(hour: Int, events: [ContextEvent])] {
        let cal = Calendar.current
        var buckets: [Int: [ContextEvent]] = [:]
        for event in events {
            let hour = cal.component(.hour, from: event.timestamp)
            buckets[hour, default: []].append(event)
        }
        return buckets
            .sorted { $0.key < $1.key }
            .map { (hour: $0.key, events: $0.value.sorted { $0.timestamp < $1.timestamp }) }
    }

    /// Total events on the selected day — used in the empty-state copy.
    var eventCount: Int { events.count }

    func select(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        guard normalized != selectedDate else { return }
        selectedDate = normalized
    }

    func refresh(context: ModelContext) {
        let logicalDate = Calendar.current.startOfDay(for: selectedDate)
        let descriptor = FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate == logicalDate },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        events = (try? context.fetch(descriptor)) ?? []
    }
}
