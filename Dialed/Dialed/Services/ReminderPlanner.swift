//
//  ReminderPlanner.swift
//  Dialed
//
//  Smart reminders: nudges that only fire when you're behind. Given where
//  today stands right now, the planner lists the reminders still worth
//  sending today — one per checkpoint you'd miss if you logged nothing
//  else from here. Logging (or a WaterH sip landing in Apple Health)
//  triggers a re-plan, which cancels anything you've since caught up on.
//
//  Pure Foundation, unit-tested. SmartReminders.swift owns scheduling.
//

import Foundation

// MARK: - Settings

enum ReminderKind: String, CaseIterable, Codable, Identifiable {
    case water, protein, weighIn, steps, weeklyReview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water:        return "Water"
        case .protein:      return "Protein & meals"
        case .weighIn:      return "Morning weigh-in"
        case .steps:        return "Evening walk"
        case .weeklyReview: return "Sunday review"
        }
    }

    var detail: String {
        switch self {
        case .water:        return "11 AM, 2, 5 and 7:30 PM — only if you're behind"
        case .protein:      return "1 and 6 PM, plus a nudge if nothing's logged since noon"
        case .weighIn:      return "7:30 AM, if you haven't stepped on the scale"
        case .steps:        return "6 PM, if you're short on steps"
        case .weeklyReview: return "Sundays at 6 PM: your week in one screen"
        }
    }

    var icon: String {
        switch self {
        case .water:        return "drop.fill"
        case .protein:      return "fork.knife"
        case .weighIn:      return "scalemass.fill"
        case .steps:        return "figure.walk"
        case .weeklyReview: return "calendar.badge.checkmark"
        }
    }
}

/// Where tapping a reminder takes you. Carried in the notification's
/// userInfo as `ReminderRoute.userInfoKey`.
enum ReminderRoute: String, Codable, Equatable {
    case water, weighIn, foodLog, weeklyReview, home

    static let userInfoKey = "dialedRoute"
}

struct ReminderSettings: Codable, Equatable {
    /// Master switch. Off until you turn it on (that's when we ask for
    /// notification permission).
    var enabled = false
    var disabledKinds: Set<ReminderKind> = []
    /// Minutes after midnight. Defaults: quiet from 9:30 PM to 7:00 AM.
    var quietStart = 21 * 60 + 30
    var quietEnd = 7 * 60
    /// Daily cap for nudges (the Sunday review doesn't count).
    var maxPerDay = 4

    static let storageKey = "smartReminders.settings.v1"

    func isOn(_ kind: ReminderKind) -> Bool {
        enabled && !disabledKinds.contains(kind)
    }

    /// True when `minuteOfDay` falls in quiet hours (handles overnight ranges).
    func isQuiet(minuteOfDay m: Int) -> Bool {
        guard quietStart != quietEnd else { return false }
        if quietStart < quietEnd { return m >= quietStart && m < quietEnd }
        return m >= quietStart || m < quietEnd
    }

    func isQuiet(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return isQuiet(minuteOfDay: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    static func load(from defaults: UserDefaults = .standard) -> ReminderSettings {
        guard let data = defaults.data(forKey: storageKey),
              let s = try? JSONDecoder().decode(ReminderSettings.self, from: data) else { return ReminderSettings() }
        return s
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

// MARK: - Planner

enum ReminderPlanner {

    struct Inputs: Equatable {
        var now: Date
        var waterOz: Double = 0
        var waterTargetOz: Double = 0
        var proteinGrams: Double = 0
        var proteinTarget: Double = 0
        var caloriesIn: Double = 0
        var calorieTarget: Double = 0
        var steps: Int = 0
        var stepGoal: Int = 10_000
        var weighedInToday = false
        /// Most recent meal / food logged today, from any source.
        var lastMealAt: Date?
        /// Smart nudges already delivered today (count against the cap).
        var deliveredToday = 0
    }

    struct Reminder: Equatable, Identifiable {
        let id: String
        let kind: ReminderKind
        let fireDate: Date
        let title: String
        let body: String
        let route: ReminderRoute
    }

    /// Identifier prefix for everything this feature schedules.
    static let idPrefix = "smart."
    /// You count as behind when under this share of where pace says you
    /// should be at the checkpoint.
    static let tolerance = 0.9
    /// Two nudges never land closer together than this.
    static let minSpacing: TimeInterval = 75 * 60

    /// Share of the day's targets you "should" have by `date`: linear from
    /// 7 AM (0) to 9 PM (1). The same pace Home's avatar mood uses.
    static func pace(at date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        return max(0, min(1, (hour - 7) / 14))
    }

    /// Today's remaining nudges, earliest first, capped and spaced.
    static func plan(_ inputs: Inputs, settings: ReminderSettings, calendar: Calendar = .current) -> [Reminder] {
        guard settings.enabled else { return [] }
        let now = inputs.now
        let dayKey = Self.dayKey(now, calendar: calendar)

        func at(_ hour: Int, _ minute: Int = 0) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
        }
        func id(_ kind: ReminderKind, _ date: Date) -> String {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return "\(idPrefix)\(kind.rawValue).\(dayKey).\(String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0))"
        }

        var candidates: [Reminder] = []

        // Weigh-in before coffee.
        if settings.isOn(.weighIn), !inputs.weighedInToday, let t = at(7, 30) {
            candidates.append(Reminder(
                id: id(.weighIn, t), kind: .weighIn, fireDate: t,
                title: "Weigh in before coffee ☕",
                body: "Scale first, then breakfast — morning weight is the one that counts.",
                route: .weighIn))
        }

        // Water checkpoints.
        if settings.isOn(.water), inputs.waterTargetOz > 0 {
            for (h, m) in [(11, 0), (14, 0), (17, 0), (19, 30)] {
                guard let t = at(h, m) else { continue }
                let goal = inputs.waterTargetOz * pace(at: t, calendar: calendar)
                guard inputs.waterOz < goal * tolerance else { continue }
                let need = Int((goal - inputs.waterOz).rounded())
                candidates.append(Reminder(
                    id: id(.water, t), kind: .water, fireDate: t,
                    title: "Water check 💧",
                    body: "\(Int(inputs.waterOz)) of \(Int(inputs.waterTargetOz)) oz so far. \(need) oz gets you back on pace — a few big pulls from the bottle.",
                    route: .water))
            }
        }

        // Protein checkpoints + the afternoon "nothing since noon" nudge.
        if settings.isOn(.protein), inputs.proteinTarget > 0 {
            let caloriesLeft = inputs.calorieTarget > 0 ? Int(inputs.calorieTarget - inputs.caloriesIn) : nil
            for h in [13, 18] {
                guard let t = at(h) else { continue }
                let goal = inputs.proteinTarget * pace(at: t, calendar: calendar)
                guard inputs.proteinGrams < goal * tolerance else { continue }
                let need = Int((goal - inputs.proteinGrams).rounded())
                var body = "\(Int(inputs.proteinGrams)) of \(Int(inputs.proteinTarget)) g protein. "
                if h == 13 {
                    body += "Make lunch count — about \(need) g (chicken, Greek yogurt, a shake) gets you on pace."
                } else if let left = caloriesLeft, left > 0 {
                    body += "\(left) calories left — a lean-protein dinner of ~\(need) g keeps you on track."
                } else {
                    body += "A ~\(need) g protein dinner keeps the day on track."
                }
                candidates.append(Reminder(
                    id: id(.protein, t), kind: .protein, fireDate: t,
                    title: h == 13 ? "Protein at lunch 🍗" : "Protein at dinner 🍗",
                    body: body, route: .foodLog))
            }

            if let t = at(15, 30), let noon = at(12),
               inputs.lastMealAt.map({ $0 < noon }) ?? true,
               inputs.proteinGrams < inputs.proteinTarget * pace(at: t, calendar: calendar) * tolerance {
                let since: String
                if let last = inputs.lastMealAt, calendar.isDate(last, inSameDayAs: now) {
                    since = "since \(timeString(last, calendar: calendar))"
                } else {
                    since = "yet today"
                }
                candidates.append(Reminder(
                    id: id(.protein, t), kind: .protein, fireDate: t,
                    title: "Nothing logged \(since)",
                    body: "You're at \(Int(inputs.proteinGrams)) g protein. Grab a protein snack and log it — 30 g goes a long way.",
                    route: .foodLog))
            }
        }

        // Evening walk.
        if settings.isOn(.steps), inputs.stepGoal > 0, let t = at(18) {
            let goal = Double(inputs.stepGoal) * pace(at: t, calendar: calendar)
            if Double(inputs.steps) < goal * tolerance {
                let short = max(0, inputs.stepGoal - inputs.steps)
                // ~110 steps a minute at an easy walking pace, rounded to 5 min.
                let minutes = max(10, min(60, Int((Double(short) / 110 / 5).rounded()) * 5))
                candidates.append(Reminder(
                    id: id(.steps, t), kind: .steps, fireDate: t,
                    title: "Time for a walk? 🚶",
                    body: "\(inputs.steps.formatted()) steps so far. A \(minutes)-min walk adds ~\((minutes * 110).formatted()) and gets you close to \(inputs.stepGoal.formatted()).",
                    route: .home))
            }
        }

        // Future only, never in quiet hours, earliest first, spaced, capped.
        let ordered = candidates
            .filter { $0.fireDate > now && !settings.isQuiet($0.fireDate, calendar: calendar) }
            .sorted { $0.fireDate < $1.fireDate }
        var kept: [Reminder] = []
        let budget = max(0, settings.maxPerDay - inputs.deliveredToday)
        for r in ordered where kept.count < budget {
            if let last = kept.last, r.fireDate.timeIntervalSince(last.fireDate) < minSpacing { continue }
            kept.append(r)
        }
        return kept
    }

    /// Tomorrow morning's weigh-in nudge, so it still fires if the app
    /// isn't opened (or refreshed in the background) before then.
    static func tomorrowWeighIn(now: Date, settings: ReminderSettings, calendar: Calendar = .current) -> Reminder? {
        guard settings.isOn(.weighIn),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let t = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow),
              !settings.isQuiet(t, calendar: calendar) else { return nil }
        return Reminder(
            id: "\(idPrefix)weighIn.\(dayKey(t, calendar: calendar)).0730", kind: .weighIn, fireDate: t,
            title: "Weigh in before coffee ☕",
            body: "Scale first, then breakfast — morning weight is the one that counts.",
            route: .weighIn)
    }

    /// The next Sunday 6 PM (today if it's Sunday before 6), as long as
    /// that's not inside quiet hours.
    static func weeklyReview(now: Date, settings: ReminderSettings, calendar: Calendar = .current) -> Reminder? {
        guard settings.isOn(.weeklyReview) else { return nil }
        let today = calendar.startOfDay(for: now)
        for ahead in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: ahead, to: today),
                  calendar.component(.weekday, from: day) == 1,     // Sunday
                  let t = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day),
                  t > now else { continue }
            if settings.isQuiet(t, calendar: calendar) { return nil }
            return Reminder(
                id: "\(idPrefix)weeklyReview", kind: .weeklyReview, fireDate: t,
                title: "Your week in review 📊",
                body: "Weight trend, best and worst day, and the one thing to fix next week.",
                route: .weeklyReview)
        }
        return nil
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func timeString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0
        let m = c.minute ?? 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let suffix = h < 12 ? "AM" : "PM"
        return m == 0 ? "\(h12) \(suffix)" : "\(h12):\(String(format: "%02d", m)) \(suffix)"
    }
}
