//
//  EventMode.swift
//  Dialed
//
//  The run-up to a big day (your brother's wedding): a countdown, then a
//  "look your best" final week — less salt and fewer carbs so you hold
//  less water, plenty to drink, sleep first — then the day itself, when
//  nothing gets tracked and nothing nags, and a no-guilt day after.
//  Pure Foundation, tested; EventModeStore reads the saved event.
//

import Foundation

enum EventMode {

    enum Phase: Equatable {
        /// More than a week out.
        case countdown(daysLeft: Int)
        /// The last seven days.
        case lookYourBest(daysLeft: Int)
        /// The day itself: have fun, track nothing.
        case eventDay
        /// The day after.
        case recovery
        /// No event, or it's well past.
        case none

        var daysLeft: Int? {
            switch self {
            case .countdown(let d), .lookYourBest(let d): return d
            case .eventDay: return 0
            default: return nil
            }
        }
    }

    static let lookYourBestDays = 7
    /// Sodium stays under this during the final week.
    static let sodiumLimitMg = 2_000
    /// A countdown before this many days out is just a date.
    static let countdownDays = 45

    static func phase(event: Date, now: Date = Date(), calendar: Calendar = .current) -> Phase {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: event)).day ?? 0
        switch days {
        case 0:                         return .eventDay
        case -1:                        return .recovery
        case 1...lookYourBestDays:      return .lookYourBest(daysLeft: days)
        case (lookYourBestDays + 1)...: return .countdown(daysLeft: days)
        default:                        return .none
        }
    }

    static func isEventDay(event: Date?, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let event else { return false }
        return calendar.isDate(event, inSameDayAs: date)
    }

    /// When the countdown is measured from: 30 days out, or the first
    /// weigh-in after that if you started later.
    static func countdownStart(event: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: event)) ?? event
    }

    // MARK: - Copy

    static func isWedding(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("wedding") || n.contains("marri")
    }

    /// "Suit-fit countdown" for a wedding, else "Countdown".
    static func countdownTitle(_ name: String) -> String {
        isWedding(name) ? "Suit-fit countdown" : "Countdown"
    }

    static func eventDayTitle(_ name: String) -> String {
        isWedding(name) ? "Enjoy the wedding 🥂" : "Enjoy \(name) 🎉"
    }

    // MARK: - Final week

    /// Carbs, moderately lower (never keto): a little lower all week, a
    /// bit lower again for the last three days.
    static func carbTarget(daysLeft: Int) -> ClosedRange<Int>? {
        switch daysLeft {
        case 1...3:                return 100...130
        case 4...lookYourBestDays: return 150...180
        default:                   return nil
        }
    }

    struct Item: Equatable, Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    /// Today's look-your-best checklist. `bedtime` is "10:30 PM" from your
    /// wake-up schedule, when there is one.
    static func checklist(daysLeft: Int, bedtime: String?) -> [Item] {
        guard (1...lookYourBestDays).contains(daysLeft) else { return [] }
        let lastTwo = daysLeft <= 2
        var items: [Item] = [
            Item(id: "sodium", symbol: "drop.triangle",
                 title: "Sodium under \(sodiumLimitMg.formatted()) mg",
                 detail: "Skip soy sauce, deli meat, chips and takeout sauces; salt is the main reason you hold water."),
        ]
        if let carbs = carbTarget(daysLeft: daysLeft) {
            items.append(Item(id: "carbs", symbol: "leaf",
                              title: "Carbs \(carbs.lowerBound)–\(carbs.upperBound) g",
                              detail: "A bit lower, not zero. Keep a fist of rice or potatoes at one meal so you don't feel flat."))
        }
        items.append(lastTwo
            ? Item(id: "water", symbol: "drop.fill", title: "Drink normally",
                   detail: "Keep sipping like usual. Cutting water now makes you look flat and feel awful, not leaner.")
            : Item(id: "water", symbol: "drop.fill", title: "100+ oz of water",
                   detail: "Plenty of water tells your body it can let go of what it's holding."))
        items.append(Item(id: "sleep", symbol: "moon.stars.fill",
                          title: bedtime.map { "In bed by \($0)" } ?? "8 hours of sleep",
                          detail: "Sleep is the best de-puffer there is. Eight hours tonight."))
        items.append(Item(id: "alcohol", symbol: "wineglass", title: "Skip the drinks",
                          detail: "Save them for the big day."))
        items.append(Item(id: "familiar", symbol: "fork.knife", title: "Familiar foods only",
                          detail: "No new restaurants or experiments this week, so nothing surprises your stomach."))
        if lastTwo {
            items.append(Item(id: "fiber", symbol: "carrot", title: "Go lighter on fiber",
                              detail: "Easy veggies (cooked, not big raw salads) and fewer beans so you're not bloated."))
        }
        return items
    }

    /// One line for the Fuel card during the final week.
    static func fuelLine(daysLeft: Int) -> String? {
        guard let carbs = carbTarget(daysLeft: daysLeft) else { return nil }
        return "Look-your-best week: carbs \(carbs.lowerBound)–\(carbs.upperBound) g, sodium under \(sodiumLimitMg.formatted()) mg."
    }
}
