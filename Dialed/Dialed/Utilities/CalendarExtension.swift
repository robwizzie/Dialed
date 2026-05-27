//
//  CalendarExtension.swift
//  Dialed
//
//  Shared Calendar helpers. The 4 AM "app day" cutoff lives here so every
//  callsite that asks "what day is today, from the app's perspective?"
//  hits the same answer — matching ContextEvent.logicalDate and
//  BiometricSnapshot.logicalDate semantics.
//

import Foundation

extension Calendar {

    /// Returns the start of the "app day" containing `date`. Applies the
    /// 4 AM cutoff: 1 AM Tuesday wall-clock returns Monday 00:00.
    ///
    /// Use this anywhere you want to filter rows by `logicalDate` —
    /// otherwise queries between midnight and 4 AM miss events the user
    /// just logged.
    func logicalStartOfDay(for date: Date) -> Date {
        let hour = component(.hour, from: date)
        let base = startOfDay(for: date)
        if hour < Constants.dayCutoffHour {
            return self.date(byAdding: .day, value: -1, to: base) ?? base
        }
        return base
    }

    /// True when `date` falls within the same "app day" as `referenceDate`
    /// (respects the 4 AM cutoff). Stand-in for `isDateInToday(_:)` when
    /// the reference is "the user's logical now".
    func isDateInLogicalDay(_ date: Date, of referenceDate: Date) -> Bool {
        logicalStartOfDay(for: date) == logicalStartOfDay(for: referenceDate)
    }
}
