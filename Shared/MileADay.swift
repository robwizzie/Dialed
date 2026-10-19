//
//  MileADay.swift
//  Dialed (app + widgets)
//
//  The daily mile: walked or run, every day. A day counts from whichever
//  is bigger: Apple Health's walking + running distance, or the on-foot
//  workouts you logged (walks, runs, hikes — several add up). With
//  neither (e.g. steps only from the Pixel Watch) it's estimated from
//  steps using your own stride — learned from days Health has both, or
//  set by hand in Settings → Mile a day, where the goal and how far back
//  your history is counted live too. Pure Foundation, tested.
//

import Foundation

/// How the daily mile is measured. Lives in the App Group so the widgets
/// score it the same way.
struct MileSettings: Codable, Equatable {
    /// Daily distance goal, in miles.
    var goalMiles: Double = 1
    /// Set by hand; wins over the learned stride.
    var manualStepsPerMile: Double?
    /// Learned from your Apple Health history (steps ÷ distance).
    var learnedStepsPerMile: Double?
    /// Count history from this day (nil → the challenge start, or 90 days).
    var historyStart: Date?

    static let defaultStepsPerMile = 2_100.0
    static let didChange = Notification.Name("MileSettings.didChange")
    private static let key = "mile.settings.v1"
    private static var store: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    var stepsPerMile: Double { manualStepsPerMile ?? learnedStepsPerMile ?? Self.defaultStepsPerMile }

    static func load() -> MileSettings {
        guard let data = store.data(forKey: key),
              let s = try? JSONDecoder().decode(MileSettings.self, from: data) else { return MileSettings() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.store.set(data, forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

enum MileADay {
    /// Today's goal in miles (1 unless changed in Settings).
    static var goal: Double { MileSettings.load().goalMiles }

    /// Today's miles: measured distance if there is any, else estimated
    /// from steps with your stride.
    static func miles(distance: Double?, steps: Int,
                      stepsPerMile: Double = MileSettings.load().stepsPerMile) -> Double {
        if let distance, distance > 0.01 { return distance }
        return Double(max(0, steps)) / max(500, stepsPerMile)
    }

    static func isDone(_ miles: Double, goal: Double = MileADay.goal) -> Bool { miles >= goal - 0.005 }

    /// One day's miles and where they came from: the bigger of measured
    /// distance and on-foot workouts, else the step estimate.
    static func resolve(distance: Double?, workoutMiles: Double, steps: Int,
                        stepsPerMile: Double) -> (miles: Double, source: MileDay.Source) {
        let d = distance ?? 0
        if max(d, workoutMiles) > 0.01 {
            return workoutMiles > d ? (workoutMiles, .workout) : (d, .distance)
        }
        let est = miles(distance: nil, steps: steps, stepsPerMile: stepsPerMile)
        return est > 0 ? (est, .steps) : (0, .none)
    }

    /// Your steps per mile from days Apple Health has both a real walk's
    /// distance and its steps: the median, so one odd day doesn't skew it.
    /// Nil until there are 3 usable days.
    static func learnStride(_ days: [(steps: Double, miles: Double)]) -> Double? {
        let ratios = days
            .filter { $0.miles >= 0.5 && $0.steps >= 1_000 }
            .map { $0.steps / $0.miles }
            .filter { (1_200...3_500).contains($0) }
            .sorted()
        guard ratios.count >= 3 else { return nil }
        let mid = ratios.count / 2
        let median = ratios.count % 2 == 1 ? ratios[mid] : (ratios[mid - 1] + ratios[mid]) / 2
        return (median / 10).rounded() * 10
    }

    /// Days in a row with the goal done, counting back from today. Today
    /// only breaks the streak once it's over, so a morning with 0.2 mi
    /// still shows yesterday's streak.
    static func streak(milesByDay: [Date: Double], today: Date, goal: Double = MileADay.goal,
                       calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        var day = isDone(milesByDay[start] ?? 0, goal: goal) ? start : (calendar.date(byAdding: .day, value: -1, to: start) ?? start)
        var count = 0
        while isDone(milesByDay[day] ?? 0, goal: goal) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    /// "1 mi", "1.5 mi".
    static func format(_ miles: Double) -> String {
        let s = miles == miles.rounded() ? String(format: "%.0f", miles) : String(format: "%g", (miles * 100).rounded() / 100)
        return "\(s) mi"
    }

    /// A short, upbeat line for where you are today.
    static func message(miles: Double, streak: Int, ran: Bool, goal: Double = MileADay.goal) -> String {
        if isDone(miles, goal: goal) {
            let how = ran ? "Ran it" : "Walked it"
            if miles >= max(3, goal * 2) { return "\(how) — \(String(format: "%.1f", miles)) miles. Overachiever." }
            return streak > 1 ? "\(how). \(streak) days in a row 🔥" : "\(how). Goal done ✓"
        }
        let left = goal - miles
        let minutes = Int((left * 20).rounded())
        if miles < 0.05 {
            return streak > 0
                ? "Keep the \(streak)-day streak alive — about \(minutes) easy minutes does it."
                : "\(format(goal)) today. About \(minutes) minutes of walking."
        }
        if left <= 0.25 { return "\(String(format: "%.2f", left)) mi to go — a lap of the block." }
        return "\(String(format: "%.2f", left)) mi to go — about \(minutes) min of walking."
    }
}

// MARK: - History

/// One day of the daily mile.
struct MileDay: Codable, Equatable {
    enum Source: String, Codable { case distance, workout, steps, none }

    var date: Date
    var miles: Double
    /// Miles from walking / running / hiking workouts that day.
    var workoutMiles: Double = 0
    var workouts: Int = 0
    var ran: Bool = false
    var source: Source = .none
}

/// Every day since `start`, worked out by the app and kept in the App
/// Group so the widgets and the history calendar read the same thing.
struct MileHistory: Codable, Equatable {
    var start: Date
    var days: [MileDay]
    var updatedAt: Date

    private static let key = "mile.history.v1"
    private static var store: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    static func load() -> MileHistory? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MileHistory.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.store.set(data, forKey: Self.key)
    }

    var milesByDay: [Date: Double] {
        Dictionary(days.map { ($0.date, $0.miles) }, uniquingKeysWith: max)
    }

    func day(_ date: Date, calendar: Calendar = .current) -> MileDay? {
        let d = calendar.startOfDay(for: date)
        return days.last { $0.date == d }
    }

    /// The last `count` days ending today, oldest first; missing days are 0.
    func last(_ count: Int, today: Date, calendar: Calendar = .current) -> [MileDay] {
        let end = calendar.startOfDay(for: today)
        return (0..<count).reversed().compactMap { back in
            guard let d = calendar.date(byAdding: .day, value: -back, to: end) else { return nil }
            return day(d, calendar: calendar) ?? MileDay(date: d, miles: 0)
        }
    }

    /// Replace days by date, keeping the list sorted.
    mutating func merge(_ fresh: [MileDay]) {
        var byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { $1 })
        for d in fresh { byDate[d.date] = d }
        days = byDate.values.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }

    func doneCount(goal: Double = MileADay.goal) -> Int {
        days.filter { MileADay.isDone($0.miles, goal: goal) }.count
    }

    func currentStreak(today: Date, goal: Double = MileADay.goal, calendar: Calendar = .current) -> Int {
        MileADay.streak(milesByDay: milesByDay, today: today, goal: goal, calendar: calendar)
    }

    func longestStreak(goal: Double = MileADay.goal, calendar: Calendar = .current) -> Int {
        var best = 0, run = 0
        var lastDone: Date?
        for d in days {
            if MileADay.isDone(d.miles, goal: goal) {
                let next = lastDone.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
                run = next == d.date ? run + 1 : 1
                lastDone = d.date
            } else {
                run = 0
                lastDone = nil
            }
            best = max(best, run)
        }
        return best
    }
}
