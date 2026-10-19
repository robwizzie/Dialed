//
//  MileADay.swift
//  Dialed (app + widgets)
//
//  The daily mile: walked or run, every day. Distance comes from Apple
//  Health's walking + running distance; when that's missing (e.g. the
//  steps only came from the Pixel Watch) it's estimated from steps.
//  Pure Foundation, tested.
//

import Foundation

enum MileADay {
    static let goal = 1.0
    /// Average steps per mile at a walking stride.
    static let stepsPerMile = 2_100.0

    /// Today's miles: measured distance if there is any, else estimated
    /// from steps.
    static func miles(distance: Double?, steps: Int) -> Double {
        if let distance, distance > 0.01 { return distance }
        return Double(max(0, steps)) / stepsPerMile
    }

    static func isDone(_ miles: Double) -> Bool { miles >= goal - 0.005 }

    /// Days in a row with a mile done, counting back from today. Today
    /// only breaks the streak once it's over, so a morning with 0.2 mi
    /// still shows yesterday's streak.
    static func streak(milesByDay: [Date: Double], today: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        var day = isDone(milesByDay[start] ?? 0) ? start : (calendar.date(byAdding: .day, value: -1, to: start) ?? start)
        var count = 0
        while isDone(milesByDay[day] ?? 0) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    /// A short, upbeat line for where you are today.
    static func message(miles: Double, streak: Int, ran: Bool) -> String {
        if isDone(miles) {
            let how = ran ? "Ran it" : "Walked it"
            if miles >= 3 { return "\(how) — \(String(format: "%.1f", miles)) miles. Overachiever." }
            return streak > 1 ? "\(how). \(streak) days in a row 🔥" : "\(how). Mile done ✓"
        }
        let left = goal - miles
        if miles < 0.05 { return streak > 0 ? "Keep the \(streak)-day streak alive — 20 easy minutes does it." : "One mile today. About 20 minutes of walking." }
        if left <= 0.25 { return "\(String(format: "%.2f", left)) mi to go — a lap of the block." }
        let minutes = Int((left * 20).rounded())
        return "\(String(format: "%.2f", left)) mi to go — about \(minutes) min of walking."
    }
}
