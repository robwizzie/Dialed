//
//  FinalPush.swift
//  Dialed
//
//  The last 14 days of the challenge, when the app tightens up: a daily
//  countdown, a stricter calorie target from the pace you need to win,
//  and an "every day counts" check-in (on plan yesterday? weighed in?
//  moved?) with a streak. Pure Foundation, tested; the check-ins and the
//  stricter target are kept in UserDefaults so every screen agrees.
//

import Foundation

enum FinalPush {

    /// Final push covers the last 14 days, counting down to the end day.
    static let windowDays = 14
    /// The tighter target never drops more than this below your usual one.
    static let maxCut: Double = 750
    static let floor: Double = 1_500

    // MARK: - Countdown

    /// Whole days from today to the end day (0 on the end day itself).
    static func daysLeft(end: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
    }

    static func isActive(end: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        (0...windowDays).contains(daysLeft(end: end, now: now, calendar: calendar))
    }

    /// The day the push begins (14 days out), at 8 AM.
    static func startMorning(end: Date, calendar: Calendar = .current) -> Date? {
        let day = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: end))
        return day.flatMap { calendar.date(bySettingHour: 8, minute: 0, second: 0, of: $0) }
    }

    /// Headline and a line underneath for the day.
    static func phase(daysLeft: Int) -> (title: String, line: String) {
        switch daysLeft {
        case ...0:  return ("Final day.", "Weigh in, stay on plan, finish it.")
        case 1:     return ("1 day left.", "Tomorrow's weigh-in is the one that counts.")
        case 2...3: return ("\(daysLeft) days left.", "No days off now. Water, protein, steps.")
        case 4...7: return ("\(daysLeft) days left.", "The last week. Tight days add up fast.")
        case 8...13: return ("\(daysLeft) days left.", "Every one counts. Stack clean days.")
        default:    return ("\(daysLeft) days. Every one counts.", "Final push starts now.")
        }
    }

    // MARK: - Target

    /// The calories that hold the pace you need, but never above your usual
    /// target, more than `maxCut` below it, or under 1,500.
    static func stricterTarget(normal: Double, pace: Double?) -> Double {
        guard let pace else { return normal }
        let lowest = max(floor, normal - maxCut)
        return (max(lowest, min(normal, pace)) / 10).rounded() * 10
    }

    // MARK: - Check-ins

    struct CheckIn: Codable, Equatable {
        var onPlan: Bool?
        var weighedIn: Bool?
        var moved: Bool?

        var isComplete: Bool { onPlan != nil && weighedIn != nil && moved != nil }
        var allYes: Bool { onPlan == true && weighedIn == true && moved == true }
        var yesCount: Int { [onPlan, weighedIn, moved].filter { $0 == true }.count }
    }

    /// Days in a row (ending today, or yesterday if today isn't done yet)
    /// with all three answered yes.
    static func streak(_ checkIns: [String: CheckIn], now: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if checkIns[key(day, calendar: calendar)]?.allYes != true {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var count = 0
        while checkIns[key(day, calendar: calendar)]?.allYes == true {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Storage

/// Check-ins and today's stricter target, shared by Home, the Food log,
/// Eating out, Siri and the widget.
enum FinalPushStore {
    private static let checkInsKey = "finalPush.checkIns"
    private static let targetKey = "finalPush.target"
    private static let targetDayKey = "finalPush.targetDay"
    static let notifyKey = "finalPush.dailyCountdown"
    static let didChange = Notification.Name("FinalPushDidChange")

    static var checkIns: [String: FinalPush.CheckIn] {
        guard let data = UserDefaults.standard.data(forKey: checkInsKey),
              let all = try? JSONDecoder().decode([String: FinalPush.CheckIn].self, from: data) else { return [:] }
        return all
    }

    static func checkIn(on date: Date = Date()) -> FinalPush.CheckIn {
        checkIns[FinalPush.key(date)] ?? FinalPush.CheckIn()
    }

    static func save(_ checkIn: FinalPush.CheckIn, on date: Date = Date()) {
        var all = checkIns
        all[FinalPush.key(date)] = checkIn
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: checkInsKey) }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Today's stricter target, while final push is on.
    static func activeTarget(now: Date = Date()) -> Double? {
        let d = UserDefaults.standard
        guard d.string(forKey: targetDayKey) == FinalPush.key(now) else { return nil }
        let v = d.double(forKey: targetKey)
        return v > 0 ? v : nil
    }

    static func setTarget(_ value: Double?, now: Date = Date()) {
        let d = UserDefaults.standard
        if let value {
            d.set(value, forKey: targetKey)
            d.set(FinalPush.key(now), forKey: targetDayKey)
        } else {
            d.removeObject(forKey: targetKey)
            d.removeObject(forKey: targetDayKey)
        }
    }

    /// Daily 8 AM countdown notification; on unless turned off.
    static var dailyCountdown: Bool {
        get { UserDefaults.standard.object(forKey: notifyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifyKey) }
    }
}
