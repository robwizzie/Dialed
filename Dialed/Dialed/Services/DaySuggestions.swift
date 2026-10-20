//
//  DaySuggestions.swift
//  Dialed
//
//  Going back in time on Home, and what's still waiting from those days:
//  heart-rate stretches you never named and gym sessions your watch
//  recorded that you never logged. Pure Foundation, tested; the loader
//  that fills it from Health lives in RecentSuggestions.swift.
//

import Foundation

enum DayNavigation {

    /// `date` moved by `days`, never past today.
    static func step(_ date: Date, by days: Int, today: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let moved = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return min(moved, calendar.startOfDay(for: today))
    }

    static func canGoForward(_ date: Date, today: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: today)
    }

    /// "Today", "Yesterday", else "Mon, Oct 19".
    static func label(_ date: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: today)).day ?? 0
        switch back {
        case 0:  return "Today"
        case 1:  return "Yesterday"
        default:
            var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }
    }
}

enum DaySuggestions {

    struct Item: Identifiable, Equatable {
        enum Kind: Equatable { case activity, workout }

        var kind: Kind
        var day: Date
        /// The heart-rate stretch to name, for `.activity`.
        var bout: ActiveBouts.Bout?
        /// The watch session to log, for `.workout`.
        var workout: DetectedWorkout?

        var id: String {
            switch kind {
            case .activity: return bout?.id ?? "activity-\(day.timeIntervalSince1970)"
            case .workout:  return "workout-\(workout?.id ?? "\(day.timeIntervalSince1970)")"
            }
        }

        var start: Date { bout?.start ?? workout?.start ?? day }
        var minutes: Double { bout?.minutes ?? workout?.minutes ?? 0 }
        var calories: Double? { bout?.calories ?? workout?.calories.map(Double.init) }

        var title: String {
            switch kind {
            case .activity: return "Active \(Int(minutes.rounded())) min"
            case .workout:  return "\(workout?.title ?? "Workout") from your watch"
            }
        }
    }

    /// Gym and bike sessions a watch recorded on a day with nothing logged.
    /// Runs and walks already count toward the mile and earned calories on
    /// their own, and other sports show as bonus burn, so they're left out.
    static func unloggedWorkouts(_ workouts: [DetectedWorkout], loggedDays: Set<Date>, dismissed: Set<String>,
                                 calendar: Calendar = .current) -> [DetectedWorkout] {
        workouts.filter { w in
            (w.kind == .strength || w.kind == .bike)
                && !loggedDays.contains(calendar.startOfDay(for: w.start))
                && !dismissed.contains(w.id)
                && w.minutes >= 10
        }
    }

    /// Everything waiting, newest first. Bouts arrive already filtered
    /// (named and dismissed ones are gone).
    static func pending(bouts: [ActiveBouts.Bout], workouts: [DetectedWorkout], loggedDays: Set<Date>,
                        dismissed: Set<String>, calendar: Calendar = .current) -> [Item] {
        let activity = bouts.map { Item(kind: .activity, day: calendar.startOfDay(for: $0.start), bout: $0) }
        let gym = unloggedWorkouts(workouts, loggedDays: loggedDays, dismissed: dismissed, calendar: calendar)
            .map { Item(kind: .workout, day: calendar.startOfDay(for: $0.start), workout: $0) }
        return (activity + gym).sorted { $0.start > $1.start }
    }
}
