//
//  SleepVisuals.swift
//  Dialed
//
//  The logic behind the sleep scenes: which morning sky a score earns
//  (radiant sunrise → mellow dawn → hazy morning → grey drizzle), and
//  tonight's plan — wake from your schedule when you've set one (else
//  your usual), bedtime = wake − your goal plus a capped slice of sleep
//  debt, and a wind-down before it. Pure Foundation, tested.
//

import Foundation

enum SleepVisuals {

    // MARK: - Morning

    enum MorningTier: Int, CaseIterable {
        case drizzly, hazy, mellow, radiant

        init(score: Int) {
            switch score {
            case 85...:   self = .radiant
            case 70..<85: self = .mellow
            case 50..<70: self = .hazy
            default:      self = .drizzly
            }
        }

        /// One line under the score.
        var verdict: String {
            switch self {
            case .radiant: return "Fully charged. Go take the day."
            case .mellow:  return "Solid night. You're good to go."
            case .hazy:    return "A little foggy. Ease into it."
            case .drizzly: return "Rough night. Be kind to yourself today."
            }
        }

        /// The verdict with how the night compares to your week folded in.
        func verdict(weekDelta: Int?) -> String {
            guard let d = weekDelta, abs(d) >= 3 else { return verdict }
            return verdict + (d > 0 ? " \(d) above your week." : " \(-d) under your week.")
        }

        var symbol: String {
            switch self {
            case .radiant: return "sun.max.fill"
            case .mellow:  return "sun.haze.fill"
            case .hazy:    return "cloud.sun.fill"
            case .drizzly: return "cloud.drizzle.fill"
            }
        }
    }

    /// How high the morning sun sits on its arc: the score as 0…1.
    static func arcProgress(score: Int) -> Double {
        min(1, max(0.04, Double(score) / 100))
    }

    // MARK: - Tonight

    enum DebtTier: Int {
        case rested, owed, heavy

        init(debtHours: Double) {
            switch debtHours {
            case ..<0.5: self = .rested
            case ..<2:   self = .owed
            default:     self = .heavy
            }
        }
    }

    struct Tonight: Equatable {
        var wake: Date
        var bedtime: Date
        var windDown: Date
        /// Hours of sleep the bedtime is planned for.
        var targetHours: Double
        var debtHours: Double
        /// Extra minutes added to pay back debt (capped).
        var extraMinutes: Int
        /// The wake time came from your wake-up schedule (an alarm you set).
        var fromSchedule: Bool

        var debtTier: DebtTier { DebtTier(debtHours: debtHours) }
    }

    /// Most debt payback one night gets — more just wrecks the next night.
    static let maxExtraMinutes = 45

    /// Tonight's plan. `learnedWakeMinutes` is your usual wake (minutes past
    /// midnight) from recent nights; the schedule wins when it has a wake
    /// time for the next morning. nil when there's neither.
    static func tonight(schedule: WakeSchedule?, learnedWakeMinutes: Int?, debtHours: Double,
                        needHours: Double = 7.5, windDownMinutes: Int? = nil,
                        now: Date = Date(), calendar: Calendar = .current) -> Tonight? {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        var wake: Date?
        var fromSchedule = false
        if let schedule {
            // Still before this morning's alarm (a late night)? That's the one.
            if let w = schedule.wake(on: today, calendar: calendar), w > now {
                wake = w
            } else {
                wake = schedule.wake(on: tomorrow, calendar: calendar)
            }
            fromSchedule = wake != nil
        }
        if wake == nil, let m = learnedWakeMinutes {
            let todayWake = calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: today) ?? today
            wake = todayWake > now ? todayWake
                : calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: tomorrow)
        }
        guard let wake else { return nil }

        let need = fromSchedule ? Double(schedule?.sleepGoalMinutes ?? 450) / 60 : needHours
        let debt = max(0, debtHours)
        let extra = min(maxExtraMinutes, Int((debt / 3 * 60).rounded()))
        let target = need + Double(extra) / 60
        let bedtime = wake.addingTimeInterval(-target * 3600)
        let wind = windDownMinutes ?? schedule?.windDownMinutes ?? 30
        return Tonight(wake: wake, bedtime: bedtime, windDown: bedtime.addingTimeInterval(-Double(wind) * 60),
                       targetHours: target, debtHours: debt, extraMinutes: extra, fromSchedule: fromSchedule)
    }

    /// Where `date` sits between `start` and `end`, 0…1.
    static func fraction(_ date: Date, from start: Date, to end: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / span))
    }

    /// "Wind down in 1 h 20 m" / "Lights out in 25 m" / "Past bedtime: lights out".
    static func countdown(_ t: Tonight, now: Date = Date()) -> String {
        func span(_ seconds: TimeInterval) -> String {
            let m = Int((seconds / 60).rounded(.up))
            return m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) m"
        }
        if now < t.windDown { return "Wind down in \(span(t.windDown.timeIntervalSince(now)))" }
        if now < t.bedtime { return "Lights out in \(span(t.bedtime.timeIntervalSince(now)))" }
        if now < t.wake { return "Past bedtime. Lights out now" }
        return "Morning!"
    }
}
