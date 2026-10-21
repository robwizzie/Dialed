//
//  WakeAlarm.swift
//  Dialed
//
//  A wake-up alarm you can't sleep through, modeled on Alarmy: it rings
//  at each scheduled wake-up (WakeSchedule, one-day changes included) and
//  only a mission turns it off for good — math, shaking, walking, a memory
//  grid, typing a line, a photo of a spot or a barcode you registered.
//  Starting the mission silences it; stalling or leaving the app brings it
//  back; a wake-up check a few minutes later makes sure you stayed up.
//  This file is the pure part (settings, fire times, re-ring rules,
//  mission content) and is tested; scheduling lives in
//  WakeAlarmScheduler, the flow in WakeAlarmCoordinator.
//

import Foundation

// MARK: - Missions

enum WakeMission: String, Codable, CaseIterable, Identifiable {
    case math, shake, steps, memory, typing, photo, barcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .math:    return "Math"
        case .shake:   return "Shake"
        case .steps:   return "Walk it off"
        case .memory:  return "Memory"
        case .typing:  return "Typing"
        case .photo:   return "Photo"
        case .barcode: return "Barcode"
        }
    }

    var symbol: String {
        switch self {
        case .math:    return "function"
        case .shake:   return "iphone.radiowaves.left.and.right"
        case .steps:   return "figure.walk"
        case .memory:  return "square.grid.3x3.fill"
        case .typing:  return "keyboard.fill"
        case .photo:   return "camera.fill"
        case .barcode: return "barcode.viewfinder"
        }
    }

    var blurb: String {
        switch self {
        case .math:    return "Solve a few problems in a row"
        case .shake:   return "Shake your phone until the ring fills"
        case .steps:   return "Get out of bed and walk"
        case .memory:  return "Repeat the pattern of lit tiles"
        case .typing:  return "Type a line exactly"
        case .photo:   return "Take a photo of a spot you registered"
        case .barcode: return "Scan a barcode you registered"
        }
    }

    /// Needs something registered first.
    var needsReference: Bool { self == .photo || self == .barcode }
}

enum MissionDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy, normal, hard
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

// MARK: - Settings

struct WakeAlarmSettings: Codable, Equatable {
    var enabled = false
    var mission: WakeMission = .math
    var difficulty: MissionDifficulty = .normal
    /// Snoozes allowed per alarm (0 or 1, like Alarmy's strict setting).
    var snoozes = 0
    var snoozeMinutes = 5
    var wakeCheck = true
    /// Registered for the barcode mission.
    var barcode: String?
    /// A photo reference is saved on disk (WakeAlarmReference).
    var hasPhotoReference = false
    /// One-off alarms on top of the schedule (tests, naps).
    var extra: [Date] = []

    private static let key = "wakeAlarm.settings"

    static func load(_ defaults: UserDefaults = .standard) -> WakeAlarmSettings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(WakeAlarmSettings.self, from: data) else { return WakeAlarmSettings() }
        return s
    }

    func save(_ defaults: UserDefaults = .standard) {
        var copy = self
        copy.extra = copy.extra.filter { $0 > Date().addingTimeInterval(-3 * 3600) }
        if let data = try? JSONEncoder().encode(copy) { defaults.set(data, forKey: Self.key) }
    }

    /// The mission that will actually run: photo/barcode fall back to math
    /// until something is registered, so the alarm can always be beaten.
    var effectiveMission: WakeMission {
        switch mission {
        case .photo where !hasPhotoReference: return .math
        case .barcode where (barcode ?? "").isEmpty: return .math
        default: return mission
        }
    }
}

// MARK: - When it rings

enum WakeAlarmPlan {

    /// Starting a mission silences the alarm; doing nothing for this long rings it again.
    static let idleTimeout: TimeInterval = 90
    /// Pressing Stop without the mission: it comes back this soon.
    static let stopReRing: TimeInterval = 30
    /// Leaving the app mid-mission: almost straight away.
    static let leaveReRing: TimeInterval = 8
    /// Wake-up check: a nudge this long after the mission…
    static let wakeCheckDelay: TimeInterval = 5 * 60
    /// …and the alarm again if it isn't answered within this.
    static let wakeCheckWindow: TimeInterval = 2 * 60
    /// A missed alarm still counts as "ringing" this long after it fired.
    static let dueWindow: TimeInterval = 3 * 3600

    enum Event { case missionStarted, progress, leftApp, stoppedWithoutMission }

    /// When the alarm rings again after `event`, unless the mission is done first.
    static func reRing(after event: Event, now: Date) -> Date {
        switch event {
        case .missionStarted, .progress: return now.addingTimeInterval(idleTimeout)
        case .leftApp:                   return now.addingTimeInterval(leaveReRing)
        case .stoppedWithoutMission:     return now.addingTimeInterval(stopReRing)
        }
    }

    /// Progress only pushes the re-ring out when it's been a while since the
    /// last push, so a stream of taps doesn't reschedule the alarm every time.
    static func shouldExtend(lastArmed: Date?, now: Date, minimumGap: TimeInterval = 20) -> Bool {
        guard let lastArmed else { return true }
        return now.timeIntervalSince(lastArmed) >= minimumGap
    }

    /// Upcoming alarm times: each scheduled wake-up in the next `days`
    /// (one-day changes respected, sleep-in days skipped) plus one-offs,
    /// future only, sorted, one per minute.
    static func fireDates(schedule: WakeSchedule, extra: [Date] = [], from now: Date, days: Int = 7,
                          calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let wake = schedule.wake(on: day, calendar: calendar), wake > now else { continue }
            dates.append(wake)
        }
        dates += extra.filter { $0 > now }
        var seen = Set<String>()
        return dates.sorted().filter { seen.insert(key($0, calendar: calendar)).inserted }
    }

    /// The alarm that's ringing (or was missed) and still needs its
    /// mission: the latest fire time in the last few hours not yet beaten.
    static func due(schedule: WakeSchedule, extra: [Date] = [], completed: Set<String>, snoozedUntil: Date? = nil,
                    now: Date, calendar: Calendar = .current) -> Date? {
        if let snoozedUntil, now < snoozedUntil { return nil }
        var candidates: [Date] = extra
        let today = calendar.startOfDay(for: now)
        for offset in -1...0 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today),
               let wake = schedule.wake(on: day, calendar: calendar) { candidates.append(wake) }
        }
        return candidates
            .filter { $0 <= now && now.timeIntervalSince($0) <= dueWindow && !completed.contains(key($0, calendar: calendar)) }
            .max()
    }

    /// "2026-10-21T06:30"
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Mission content

enum MissionContent {

    struct Problem: Equatable {
        let text: String
        let answer: Int
    }

    /// Small deterministic generator so a mission is the same if the view redraws.
    struct Seeded {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next(_ range: ClosedRange<Int>) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int((state >> 33) % span)
        }
    }

    static func problemCount(_ d: MissionDifficulty) -> Int {
        switch d { case .easy: return 2; case .normal: return 3; case .hard: return 4 }
    }

    /// Easy: 2-digit addition. Normal: a × b + c. Hard: 2-digit × 1-digit + 2-digit.
    static func mathProblems(_ d: MissionDifficulty, seed: UInt64) -> [Problem] {
        var rng = Seeded(seed)
        return (0..<problemCount(d)).map { _ in
            switch d {
            case .easy:
                let a = rng.next(12...59), b = rng.next(11...39)
                return Problem(text: "\(a) + \(b)", answer: a + b)
            case .normal:
                let a = rng.next(3...9), b = rng.next(4...12), c = rng.next(10...49)
                return Problem(text: "\(a) × \(b) + \(c)", answer: a * b + c)
            case .hard:
                let a = rng.next(13...39), b = rng.next(3...9), c = rng.next(21...89)
                return Problem(text: "\(a) × \(b) + \(c)", answer: a * b + c)
            }
        }
    }

    static func shakes(_ d: MissionDifficulty) -> Int {
        switch d { case .easy: return 30; case .normal: return 50; case .hard: return 80 }
    }

    static func steps(_ d: MissionDifficulty) -> Int {
        switch d { case .easy: return 20; case .normal: return 40; case .hard: return 70 }
    }

    /// Grid side, tiles lit per round, rounds.
    static func memory(_ d: MissionDifficulty) -> (side: Int, tiles: Int, rounds: Int) {
        switch d {
        case .easy:   return (3, 3, 2)
        case .normal: return (3, 4, 3)
        case .hard:   return (4, 5, 3)
        }
    }

    /// `count` distinct tiles in a side×side grid.
    static func memoryPattern(side: Int, count: Int, seed: UInt64) -> Set<Int> {
        var rng = Seeded(seed)
        var picked = Set<Int>()
        while picked.count < min(count, side * side) { picked.insert(rng.next(0...(side * side - 1))) }
        return picked
    }

    /// The line to type — about the race when there is one.
    static func phrase(friend: String?, difficulty: MissionDifficulty, seed: UInt64) -> String {
        var rng = Seeded(seed)
        let rival = friend.flatMap { $0.isEmpty ? nil : $0 }
        let short = rival.map { ["I'm beating \($0) today.", "\($0) is still asleep. I'm not."] }
            ?? ["I am up and I am dialed in.", "Today I keep my promise."]
        let long = rival.map { ["Every choice today puts more distance between me and \($0).",
                                "I got up while \($0) hit snooze, and that is how I win this."] }
            ?? ["I get up, I drink water, I move, and I keep the streak alive.",
                "The version of me who wins this got out of bed right away."]
        let pool = difficulty == .hard ? long : (difficulty == .easy ? short : short + long)
        return pool[rng.next(0...(pool.count - 1))]
    }

    /// Typed text counts if it matches ignoring case and outer spaces.
    static func typedMatches(_ typed: String, _ phrase: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Photo match

enum PhotoMatch {
    /// Largest Vision feature-print distance still treated as "the same spot".
    static func threshold(_ d: MissionDifficulty) -> Float {
        switch d { case .easy: return 0.9; case .normal: return 0.7; case .hard: return 0.55 }
    }

    static func isMatch(distance: Float, difficulty: MissionDifficulty) -> Bool {
        distance.isFinite && distance >= 0 && distance <= threshold(difficulty)
    }
}
