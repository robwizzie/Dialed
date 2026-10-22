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

    /// Has an Easy / Medium / Hard setting.
    var hasDifficulty: Bool { self != .barcode }
}

/// Stored as easy / normal / hard (older saves); shown as Easy / Medium / Hard.
enum MissionDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy, normal, hard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .easy:   return "Easy"
        case .normal: return "Medium"
        case .hard:   return "Hard"
        }
    }
    /// One step up (Hard stays Hard).
    var harder: MissionDifficulty { self == .easy ? .normal : .hard }
}

/// How the mission is chosen when the alarm rings.
enum MissionPickMode: String, Codable, CaseIterable, Identifiable {
    /// Always the one picked.
    case single
    /// Any mission that can run.
    case randomAny
    /// One of the missions ticked.
    case randomFrom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .single:     return "One"
        case .randomAny:  return "Random"
        case .randomFrom: return "Mix"
        }
    }
}

/// What the alarm will ask for, for labels ("Math mission", "Random mission").
struct MissionSummary: Equatable {
    let title: String
    let symbol: String
    /// The mission when it's always the same one; nil when it's random.
    let single: WakeMission?
}

// MARK: - Per-mission options

/// Difficulty and size for each mission. Picking a difficulty sets sensible
/// counts; the counts can then be tuned on their own.
struct MissionTuning: Codable, Equatable {
    var mathDifficulty: MissionDifficulty = .normal
    var mathProblems = 3
    var memoryDifficulty: MissionDifficulty = .normal
    var memoryGrid = 3
    var memoryTiles = 4
    var memoryRounds = 3
    var shakeDifficulty: MissionDifficulty = .normal
    var shakes = 50
    var stepsDifficulty: MissionDifficulty = .normal
    var steps = 40
    var typingDifficulty: MissionDifficulty = .normal
    var typingLines = 1
    var photoDifficulty: MissionDifficulty = .normal

    static let problemRange = 1...10
    static let gridRange = 3...6
    static let roundRange = 1...6
    static let shakeRange = 10...300
    static let stepRange = 10...300
    static let lineRange = 1...3

    /// Squares to remember on a `grid`×`grid` board: at least 2, at most half of it.
    static func tileRange(grid: Int) -> ClosedRange<Int> { 2...max(2, grid * grid / 2) }

    init() {}

    /// Every mission at `difficulty` (how older single-difficulty settings load).
    init(preset difficulty: MissionDifficulty) {
        for m in WakeMission.allCases { setDifficulty(difficulty, for: m) }
    }

    func difficulty(for mission: WakeMission) -> MissionDifficulty {
        switch mission {
        case .math:    return mathDifficulty
        case .memory:  return memoryDifficulty
        case .shake:   return shakeDifficulty
        case .steps:   return stepsDifficulty
        case .typing:  return typingDifficulty
        case .photo:   return photoDifficulty
        case .barcode: return .normal
        }
    }

    /// Sets the difficulty and the counts that go with it.
    mutating func setDifficulty(_ d: MissionDifficulty, for mission: WakeMission) {
        switch mission {
        case .math:
            mathDifficulty = d
            mathProblems = MissionContent.problemCount(d)
        case .memory:
            memoryDifficulty = d
            let p = MissionContent.memory(d)
            memoryGrid = p.side; memoryTiles = p.tiles; memoryRounds = p.rounds
        case .shake:
            shakeDifficulty = d
            shakes = MissionContent.shakes(d)
        case .steps:
            stepsDifficulty = d
            steps = MissionContent.steps(d)
        case .typing:
            typingDifficulty = d
            typingLines = d == .hard ? 2 : 1
        case .photo:
            photoDifficulty = d
        case .barcode:
            break
        }
    }

    /// Counts kept inside their ranges (and squares inside the grid).
    func clamped() -> MissionTuning {
        var t = self
        t.mathProblems = t.mathProblems.clamped(to: Self.problemRange)
        t.memoryGrid = t.memoryGrid.clamped(to: Self.gridRange)
        t.memoryTiles = t.memoryTiles.clamped(to: Self.tileRange(grid: t.memoryGrid))
        t.memoryRounds = t.memoryRounds.clamped(to: Self.roundRange)
        t.shakes = t.shakes.clamped(to: Self.shakeRange)
        t.steps = t.steps.clamped(to: Self.stepRange)
        t.typingLines = t.typingLines.clamped(to: Self.lineRange)
        return t
    }

    /// "Snooze makes it harder": each level bumps the difficulty a step and
    /// adds a little more to do. Photo and barcode stay as they are so they
    /// can always be beaten.
    func harder(by levels: Int, for mission: WakeMission) -> MissionTuning {
        guard levels > 0 else { return self }
        var t = self
        for _ in 0..<levels {
            switch mission {
            case .math:
                t.mathDifficulty = t.mathDifficulty.harder
                t.mathProblems += 1
            case .memory:
                t.memoryDifficulty = t.memoryDifficulty.harder
                t.memoryTiles += 1
            case .shake:
                t.shakes = t.shakes * 6 / 5 + 5
            case .steps:
                t.steps = t.steps * 6 / 5 + 5
            case .typing:
                t.typingDifficulty = t.typingDifficulty.harder
            case .photo, .barcode:
                break
            }
        }
        return t.clamped()
    }

    /// One line under the mission: "3 problems · Medium".
    func summary(for mission: WakeMission) -> String {
        let d = difficulty(for: mission).title
        switch mission {
        case .math:    return "\(mathProblems) problem\(mathProblems == 1 ? "" : "s") · \(d)"
        case .memory:  return "\(memoryTiles) of \(memoryGrid * memoryGrid) squares · \(memoryRounds) round\(memoryRounds == 1 ? "" : "s") · \(d)"
        case .shake:   return "\(shakes) shakes"
        case .steps:   return "\(steps) steps"
        case .typing:  return "\(typingLines) line\(typingLines == 1 ? "" : "s") · \(d)"
        case .photo:   return "\(d) match"
        case .barcode: return "Exact code"
        }
    }
}

extension MissionTuning {
    private enum CodingKeys: String, CodingKey {
        case mathDifficulty, mathProblems, memoryDifficulty, memoryGrid, memoryTiles, memoryRounds,
             shakeDifficulty, shakes, stepsDifficulty, steps, typingDifficulty, typingLines, photoDifficulty
    }

    /// Missing fields keep their defaults, so adding options never breaks a save.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mathDifficulty = try c.decodeIfPresent(MissionDifficulty.self, forKey: .mathDifficulty) ?? mathDifficulty
        mathProblems = try c.decodeIfPresent(Int.self, forKey: .mathProblems) ?? mathProblems
        memoryDifficulty = try c.decodeIfPresent(MissionDifficulty.self, forKey: .memoryDifficulty) ?? memoryDifficulty
        memoryGrid = try c.decodeIfPresent(Int.self, forKey: .memoryGrid) ?? memoryGrid
        memoryTiles = try c.decodeIfPresent(Int.self, forKey: .memoryTiles) ?? memoryTiles
        memoryRounds = try c.decodeIfPresent(Int.self, forKey: .memoryRounds) ?? memoryRounds
        shakeDifficulty = try c.decodeIfPresent(MissionDifficulty.self, forKey: .shakeDifficulty) ?? shakeDifficulty
        shakes = try c.decodeIfPresent(Int.self, forKey: .shakes) ?? shakes
        stepsDifficulty = try c.decodeIfPresent(MissionDifficulty.self, forKey: .stepsDifficulty) ?? stepsDifficulty
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? steps
        typingDifficulty = try c.decodeIfPresent(MissionDifficulty.self, forKey: .typingDifficulty) ?? typingDifficulty
        typingLines = try c.decodeIfPresent(Int.self, forKey: .typingLines) ?? typingLines
        photoDifficulty = try c.decodeIfPresent(MissionDifficulty.self, forKey: .photoDifficulty) ?? photoDifficulty
        self = clamped()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mathDifficulty, forKey: .mathDifficulty)
        try c.encode(mathProblems, forKey: .mathProblems)
        try c.encode(memoryDifficulty, forKey: .memoryDifficulty)
        try c.encode(memoryGrid, forKey: .memoryGrid)
        try c.encode(memoryTiles, forKey: .memoryTiles)
        try c.encode(memoryRounds, forKey: .memoryRounds)
        try c.encode(shakeDifficulty, forKey: .shakeDifficulty)
        try c.encode(shakes, forKey: .shakes)
        try c.encode(stepsDifficulty, forKey: .stepsDifficulty)
        try c.encode(steps, forKey: .steps)
        try c.encode(typingDifficulty, forKey: .typingDifficulty)
        try c.encode(typingLines, forKey: .typingLines)
        try c.encode(photoDifficulty, forKey: .photoDifficulty)
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

// MARK: - Settings

struct WakeAlarmSettings: Codable, Equatable {
    var enabled = false
    /// The mission in "One" mode.
    var mission: WakeMission = .math
    var pickMode: MissionPickMode = .single
    /// The missions "Mix" picks from.
    var randomPool: [WakeMission] = [.math, .memory, .typing]
    var tuning = MissionTuning()

    var snoozeEnabled = false
    /// Snoozes allowed per alarm (when not unlimited).
    var snoozes = 1
    var snoozeUnlimited = false
    var snoozeMinutes = 5
    /// Each snooze makes the mission a step harder.
    var snoozeHarder = false

    var sound: AlarmSound = .system
    /// Start quiet and build up (Dialed's own sounds only).
    var soundRamp = false

    var wakeCheck = true
    /// Registered for the barcode mission.
    var barcode: String?
    /// A photo reference is saved on disk (WakeAlarmReference).
    var hasPhotoReference = false
    /// One-off alarms on top of the schedule (tests, naps).
    var extra: [Date] = []

    static let snoozeRange = 1...10
    static let snoozeMinuteRange = 1...30

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

    // MARK: Missions

    /// Photo and barcode can only run once something is registered.
    func canRun(_ m: WakeMission) -> Bool {
        switch m {
        case .photo:   return hasPhotoReference
        case .barcode: return !(barcode ?? "").isEmpty
        default:       return true
        }
    }

    /// The missions an alarm can pick from. Never empty: math is the
    /// fallback, so the alarm can always be beaten.
    var missionPool: [WakeMission] {
        let pool: [WakeMission]
        switch pickMode {
        case .single:     pool = [mission]
        case .randomAny:  pool = WakeMission.allCases
        case .randomFrom: pool = WakeMission.allCases.filter { randomPool.contains($0) }
        }
        let runnable = pool.filter(canRun)
        return runnable.isEmpty ? [.math] : runnable
    }

    /// The mission for the alarm with this seed: stable, so a relaunch
    /// mid-mission gets the same one.
    func mission(seed: UInt64) -> WakeMission {
        let pool = missionPool
        var rng = MissionContent.Seeded(seed)
        return pool[rng.next(0...(pool.count - 1))]
    }

    /// For labels: the one mission, or "Random".
    var effectiveMission: MissionSummary {
        let pool = missionPool
        if pool.count == 1, let only = pool.first {
            return MissionSummary(title: only.title, symbol: only.symbol, single: only)
        }
        return MissionSummary(title: "Random", symbol: "dice.fill", single: nil)
    }

    // MARK: Snooze

    /// Whether another snooze is allowed after `used`.
    func canSnooze(used: Int) -> Bool {
        snoozeEnabled && (snoozeUnlimited || used < snoozes)
    }

    /// "Snooze 5 min · 2 left"
    func snoozeLabel(used: Int) -> String {
        let left = snoozeUnlimited ? "" : " · \(max(0, snoozes - used)) left"
        return "Snooze \(snoozeMinutes) min\(left)"
    }
}

extension WakeAlarmSettings {
    private enum CodingKeys: String, CodingKey {
        case enabled, mission, pickMode, randomPool, tuning
        case difficulty   // older saves: one difficulty for every mission
        case snoozeEnabled, snoozes, snoozeUnlimited, snoozeMinutes, snoozeHarder
        case sound, soundRamp, wakeCheck, barcode, hasPhotoReference, extra
    }

    /// Every field is optional so older saves (and future ones) still load.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        mission = (try? c.decodeIfPresent(WakeMission.self, forKey: .mission)) ?? mission
        pickMode = (try? c.decodeIfPresent(MissionPickMode.self, forKey: .pickMode)) ?? pickMode
        if let raw = try? c.decodeIfPresent([String].self, forKey: .randomPool) {
            randomPool = raw.compactMap(WakeMission.init(rawValue:))
        }
        if let t = try? c.decodeIfPresent(MissionTuning.self, forKey: .tuning) {
            tuning = t
        } else if let legacy = try? c.decodeIfPresent(MissionDifficulty.self, forKey: .difficulty) {
            tuning = MissionTuning(preset: legacy)
        }
        let storedSnoozes = try c.decodeIfPresent(Int.self, forKey: .snoozes)
        if let on = try c.decodeIfPresent(Bool.self, forKey: .snoozeEnabled) {
            snoozeEnabled = on
            snoozes = storedSnoozes ?? snoozes
        } else {
            // Older saves: `snoozes` was 0 (off) or 1.
            snoozeEnabled = (storedSnoozes ?? 0) > 0
            snoozes = max(1, storedSnoozes ?? 1)
        }
        snoozes = snoozes.clamped(to: Self.snoozeRange)
        snoozeUnlimited = try c.decodeIfPresent(Bool.self, forKey: .snoozeUnlimited) ?? snoozeUnlimited
        snoozeMinutes = (try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? snoozeMinutes).clamped(to: Self.snoozeMinuteRange)
        snoozeHarder = try c.decodeIfPresent(Bool.self, forKey: .snoozeHarder) ?? snoozeHarder
        sound = (try? c.decodeIfPresent(AlarmSound.self, forKey: .sound)) ?? sound
        soundRamp = try c.decodeIfPresent(Bool.self, forKey: .soundRamp) ?? soundRamp
        wakeCheck = try c.decodeIfPresent(Bool.self, forKey: .wakeCheck) ?? wakeCheck
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        hasPhotoReference = try c.decodeIfPresent(Bool.self, forKey: .hasPhotoReference) ?? hasPhotoReference
        extra = try c.decodeIfPresent([Date].self, forKey: .extra) ?? extra
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(mission, forKey: .mission)
        try c.encode(pickMode, forKey: .pickMode)
        try c.encode(randomPool, forKey: .randomPool)
        try c.encode(tuning, forKey: .tuning)
        try c.encode(snoozeEnabled, forKey: .snoozeEnabled)
        try c.encode(snoozes, forKey: .snoozes)
        try c.encode(snoozeUnlimited, forKey: .snoozeUnlimited)
        try c.encode(snoozeMinutes, forKey: .snoozeMinutes)
        try c.encode(snoozeHarder, forKey: .snoozeHarder)
        try c.encode(sound, forKey: .sound)
        try c.encode(soundRamp, forKey: .soundRamp)
        try c.encode(wakeCheck, forKey: .wakeCheck)
        try c.encodeIfPresent(barcode, forKey: .barcode)
        try c.encode(hasPhotoReference, forKey: .hasPhotoReference)
        try c.encode(extra, forKey: .extra)
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
    /// An alarm that rang still needs its mission this long after it rang
    /// (or after the snooze ran out). Past that it's left alone.
    static let dueWindow: TimeInterval = 60 * 60
    /// How long rung alarms are remembered for `due`.
    static let armedMemory: TimeInterval = 12 * 3600

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

    /// The alarm that's ringing (or just rang) and still needs its mission.
    /// Only times an alarm was actually armed for count (`armed`), so turning
    /// alarms on, or moving today's wake-up earlier, never asks for a mission
    /// for a time that already passed without ringing. The latest one that
    /// rang within `dueWindow` (counted from the end of a snooze) and isn't
    /// beaten yet wins.
    static func due(armed: [Date], completed: Set<String>, snoozedUntil: Date? = nil,
                    now: Date, calendar: Calendar = .current) -> Date? {
        if let snoozedUntil, now < snoozedUntil { return nil }
        return armed
            .filter { fire in
                guard fire <= now, !completed.contains(key(fire, calendar: calendar)) else { return false }
                let anchor = max(fire, snoozedUntil ?? fire)
                return now.timeIntervalSince(anchor) <= dueWindow
            }
            .max()
    }

    /// "2026-10-21T06:30"
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// "in 7 h 45 m", "in 12 m", "in under a minute"
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        guard minutes > 0 else { return "in under a minute" }
        let d = minutes / 1440, h = minutes % 1440 / 60, m = minutes % 60
        if d > 0 { return h > 0 ? "in \(d) d \(h) h" : "in \(d) d" }
        if h > 0 { return m > 0 ? "in \(h) h \(m) m" : "in \(h) h" }
        return "in \(m) m"
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

    static func mathProblems(_ d: MissionDifficulty, seed: UInt64) -> [Problem] {
        mathProblems(d, count: problemCount(d), seed: seed)
    }

    /// Easy: 2-digit addition. Medium: a × b + c. Hard: 2-digit × 1-digit + 2-digit.
    static func mathProblems(_ d: MissionDifficulty, count: Int, seed: UInt64) -> [Problem] {
        var rng = Seeded(seed)
        return (0..<max(1, count)).map { _ in
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

    /// How long the pattern stays lit.
    static func memoryFlash(_ d: MissionDifficulty) -> TimeInterval {
        switch d { case .easy: return 2.4; case .normal: return 1.6; case .hard: return 1.0 }
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

    /// `lines` different lines joined into one to type.
    static func phrase(friend: String?, difficulty: MissionDifficulty, lines: Int, seed: UInt64) -> String {
        var out: [String] = []
        var attempt: UInt64 = 0
        while out.count < max(1, lines), attempt < 20 {
            let line = phrase(friend: friend, difficulty: difficulty, seed: seed &+ attempt &* 104_729)
            if !out.contains(line) { out.append(line) }
            attempt += 1
        }
        return out.joined(separator: " ")
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
