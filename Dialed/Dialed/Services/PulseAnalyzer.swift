//
//  PulseAnalyzer.swift
//  Dialed
//
//  Pulse Check: what your heart did during a scary movie, a big game, a
//  boss fight or a cold plunge. Templates say what counts as a moment
//  (a spike for a jump scare, a dip for meditation) and how to talk about
//  it; the analyzer finds the moments against a rolling baseline, scores
//  the session 0–100 and ranks sessions against each other. Pure
//  Foundation, tested.
//

import Foundation

// MARK: - Templates

enum PulseTemplate: String, Codable, CaseIterable, Identifiable {
    case scaryMovie, sportsGame, gaming, thrillRide, bigMoment, gameNight, concert, coldPlunge, meditation

    var id: String { rawValue }

    enum Direction: String, Codable { case spike, dip }

    var title: String {
        switch self {
        case .scaryMovie: return "Scary movie"
        case .sportsGame: return "Watching the game"
        case .gaming:     return "Boss fight"
        case .thrillRide: return "Roller coaster"
        case .bigMoment:  return "Big moment"
        case .gameNight:  return "Game night"
        case .concert:    return "Concert"
        case .coldPlunge: return "Cold plunge"
        case .meditation: return "Meditation"
        }
    }

    var emoji: String {
        switch self {
        case .scaryMovie: return "🎬"
        case .sportsGame: return "🏈"
        case .gaming:     return "🎮"
        case .thrillRide: return "🎢"
        case .bigMoment:  return "🎤"
        case .gameNight:  return "🃏"
        case .concert:    return "🎸"
        case .coldPlunge: return "🧊"
        case .meditation: return "🧘"
        }
    }

    var symbol: String {
        switch self {
        case .scaryMovie: return "film.fill"
        case .sportsGame: return "sportscourt.fill"
        case .gaming:     return "gamecontroller.fill"
        case .thrillRide: return "tram.fill"
        case .bigMoment:  return "person.wave.2.fill"
        case .gameNight:  return "suit.spade.fill"
        case .concert:    return "music.mic"
        case .coldPlunge: return "snowflake"
        case .meditation: return "leaf.fill"
        }
    }

    /// One line on the picker.
    var pitch: String {
        switch self {
        case .scaryMovie: return "Find the jump scares that actually got you"
        case .sportsGame: return "How stressed did the game make you?"
        case .gaming:     return "Boss fights, ranked matches, clutch rounds"
        case .thrillRide: return "Every drop, measured"
        case .bigMoment:  return "Presentations, interviews, first dates"
        case .gameNight:  return "Poker face or pounding heart?"
        case .concert:    return "When the drop hit"
        case .coldPlunge: return "The shock, then the settle"
        case .meditation: return "How low can you go?"
        }
    }

    var direction: Direction { self == .meditation ? .dip : .spike }

    /// What the analyzer calls one moment.
    var momentName: String {
        switch self {
        case .scaryMovie: return "Jump scare"
        case .sportsGame: return "Heart-stopper"
        case .gaming:     return "Panic moment"
        case .thrillRide: return "Drop"
        case .bigMoment:  return "Nerves spike"
        case .gameNight:  return "Big hand"
        case .concert:    return "Drop"
        case .coldPlunge: return "Shock"
        case .meditation: return "Deep calm"
        }
    }

    var scoreName: String {
        switch self {
        case .scaryMovie: return "Scare score"
        case .sportsGame: return "Stress score"
        case .gaming:     return "Panic score"
        case .thrillRide: return "Thrill score"
        case .bigMoment:  return "Nerves score"
        case .gameNight:  return "Tilt score"
        case .concert:    return "Hype score"
        case .coldPlunge: return "Shock score"
        case .meditation: return "Calm score"
        }
    }

    /// The big button while it's running.
    var markButton: String {
        switch self {
        case .scaryMovie: return "That got me! 😱"
        case .sportsGame: return "My heart! 😬"
        case .gaming:     return "Clutch! 😤"
        case .thrillRide: return "Here we go! 🎢"
        case .bigMoment:  return "Nervous! 😅"
        case .gameNight:  return "All in! 🃏"
        case .concert:    return "This song! 🔥"
        case .coldPlunge: return "Going in! 🥶"
        case .meditation: return "Felt calm 🌿"
        }
    }

    /// What to call the thing you watched or did.
    var titlePrompt: String {
        switch self {
        case .scaryMovie: return "Which movie?"
        case .sportsGame: return "Who's playing?"
        case .gaming:     return "What game?"
        case .thrillRide: return "Which ride or park?"
        case .bigMoment:  return "What's the moment?"
        case .gameNight:  return "What are you playing?"
        case .concert:    return "Who are you seeing?"
        case .coldPlunge: return "Plunge or sauna?"
        case .meditation: return "What kind of session?"
        }
    }

    /// Movie search only makes sense for movies.
    var searchesMovies: Bool { self == .scaryMovie }

    /// What the self-rating slider measures ("How scared were you?").
    var feltLabel: String {
        switch self {
        case .scaryMovie: return "How scared were you?"
        case .sportsGame: return "How stressed were you?"
        case .gaming:     return "How tense was it?"
        case .thrillRide: return "How scared were you?"
        case .bigMoment:  return "How nervous were you?"
        case .gameNight:  return "How tilted were you?"
        case .concert:    return "How hyped were you?"
        case .coldPlunge: return "How cold was it?"
        case .meditation: return "How calm did you feel?"
        }
    }

    /// A line for the recap, by score.
    func verdict(_ score: Int) -> String {
        switch (self.direction, score) {
        case (.dip, 70...):    return "Monk mode. Your heart barely noticed the world."
        case (.dip, 40..<70):  return "Nicely settled. You found the quiet."
        case (.dip, _):        return "Mind still racing. That's normal; it gets easier."
        case (_, 80...):
            return self == .scaryMovie ? "Absolutely terrifying. Your heart filed a complaint." : "Off the charts. Your heart was in it."
        case (_, 60..<80):
            return self == .scaryMovie ? "Properly scary. A few of those got you good." : "Big swings. That one got your pulse going."
        case (_, 35..<60):
            return self == .scaryMovie ? "Some solid scares, but you held it together." : "A few jolts, mostly in control."
        default:
            return self == .scaryMovie ? "Ice in your veins. This one barely moved you." : "Cool as anything. Barely a blip."
        }
    }
}

// MARK: - Analysis

enum PulseAnalyzer {

    struct Sample: Codable, Equatable {
        /// Seconds since the session started.
        var t: Double
        var bpm: Double
    }

    struct Settings: Equatable {
        /// bpm above the rolling baseline that counts as a spike.
        var rise: Double = 12
        /// The jump has to happen within this many seconds.
        var riseWindow: Double = 45
        /// Spikes this close together are one moment.
        var merge: Double = 60
        /// Rolling baseline: the median of this window before each reading…
        var baselineWindow: Double = 180
        /// …ending this many seconds before it, so the spike itself doesn't count.
        var baselineGap: Double = 30
        /// A manual mark within this many seconds confirms a moment.
        var markRadius: Double = 90
    }

    struct Moment: Codable, Equatable, Identifiable {
        var id: Int
        /// Seconds since start, at the peak.
        var t: Double
        var peak: Double
        var baseline: Double
        /// How far above (spike) or below (dip) the baseline it went.
        var delta: Double
        /// You tapped the button around then.
        var marked: Bool
        /// 0–1: higher when the jump was sharp or you marked it.
        var confidence: Double
    }

    struct Result: Codable, Equatable {
        var duration: Double
        var baseline: Double
        var average: Double
        var peak: Double
        var peakT: Double
        var low: Double
        var lowT: Double
        /// Minutes spent well above (or, for calm sessions, below) the baseline.
        var minutesElevated: Double
        var moments: [Moment]
        /// Marks with no heart-rate moment near them.
        var unmatchedMarks: [Double]
        var score: Int

        var biggest: Moment? { moments.max { $0.delta < $1.delta } }
        var hasData: Bool { average > 0 }
    }

    static func analyze(_ raw: [Sample], duration: Double, marks: [Double] = [],
                        direction: PulseTemplate.Direction = .spike, settings: Settings = Settings()) -> Result {
        let samples = raw.filter { $0.bpm > 30 && $0.bpm < 230 && $0.t >= -60 && $0.t <= duration + 60 }
            .sorted { $0.t < $1.t }
        guard samples.count >= 3 else {
            return Result(duration: duration, baseline: 0, average: 0, peak: 0, peakT: 0, low: 0, lowT: 0,
                          minutesElevated: 0, moments: [], unmatchedMarks: marks, score: 0)
        }
        let opening = samples.filter { $0.t <= 300 }
        let overall = median((opening.count >= 3 ? opening : samples).map(\.bpm))
        let baselines = samples.map { s in rollingBaseline(at: s.t, in: samples, settings: settings) ?? overall }

        // Candidate readings: far enough from the baseline, and (for spikes) a quick rise.
        var groups: [[Int]] = []
        for (i, s) in samples.enumerated() {
            let delta = direction == .spike ? s.bpm - baselines[i] : baselines[i] - s.bpm
            let threshold = direction == .spike ? settings.rise : settings.rise * 0.6
            guard delta >= threshold else { continue }
            if let last = groups.last?.last, s.t - samples[last].t <= settings.merge {
                groups[groups.count - 1].append(i)
            } else {
                groups.append([i])
            }
        }

        var moments: [Moment] = []
        for g in groups {
            let best = g.max { a, b in
                let da = direction == .spike ? samples[a].bpm - baselines[a] : baselines[a] - samples[a].bpm
                let db = direction == .spike ? samples[b].bpm - baselines[b] : baselines[b] - samples[b].bpm
                return da < db
            }!
            let s = samples[best]
            let delta = direction == .spike ? s.bpm - baselines[best] : baselines[best] - s.bpm
            // Sharpness: how fast it climbed from the lowest reading just before.
            let before = samples.filter { $0.t >= s.t - settings.riseWindow && $0.t <= s.t }
            let climb = direction == .spike ? s.bpm - (before.map(\.bpm).min() ?? s.bpm) : (before.map(\.bpm).max() ?? s.bpm) - s.bpm
            let sharp = min(1, climb / max(1, settings.rise))
            let marked = marks.contains { abs($0 - s.t) <= settings.markRadius }
            moments.append(Moment(id: moments.count, t: s.t, peak: s.bpm, baseline: baselines[best].rounded(),
                                  delta: delta.rounded(), marked: marked,
                                  confidence: min(1, 0.45 + 0.3 * sharp + (marked ? 0.4 : 0))))
        }
        let unmatched = marks.filter { m in !moments.contains { abs($0.t - m) <= settings.markRadius } }

        // Time well away from the opening baseline (gaps capped at 2 min).
        var elevated = 0.0
        for (i, s) in samples.enumerated() {
            let off = direction == .spike ? s.bpm - overall : overall - s.bpm
            guard off >= settings.rise / 2 else { continue }
            let next = i + 1 < samples.count ? samples[i + 1].t : s.t + 60
            elevated += min(120, max(0, next - s.t))
        }

        let peak = samples.max { $0.bpm < $1.bpm }!
        let low = samples.min { $0.bpm < $1.bpm }!
        let average = samples.map(\.bpm).reduce(0, +) / Double(samples.count)
        let score = direction == .spike
            ? spikeScore(moments: moments, elevated: elevated, duration: duration)
            : calmScore(samples: samples, baseline: overall, settings: settings)

        return Result(duration: duration, baseline: overall.rounded(), average: average.rounded(),
                      peak: peak.bpm, peakT: peak.t, low: low.bpm, lowT: low.t,
                      minutesElevated: (elevated / 60).rounded(), moments: moments,
                      unmatchedMarks: unmatched, score: score)
    }

    /// Median of the readings in the window that ends a little before `t`.
    static func rollingBaseline(at t: Double, in samples: [Sample], settings: Settings) -> Double? {
        let window = samples.filter { $0.t >= t - settings.baselineGap - settings.baselineWindow && $0.t <= t - settings.baselineGap }
        guard window.count >= 3 else { return nil }
        return median(window.map(\.bpm))
    }

    /// How many moments an hour, how big the top three were, and how long
    /// you stayed up there.
    static func spikeScore(moments: [Moment], elevated: Double, duration: Double) -> Int {
        guard duration > 0 else { return 0 }
        let hours = max(0.5, duration / 3600)
        let perHour = Double(moments.count) / hours
        let top = moments.map(\.delta).sorted(by: >).prefix(3)
        let magnitude = top.isEmpty ? 0 : top.reduce(0, +) / Double(top.count)
        let share = elevated / duration
        let raw = min(1, perHour / 6) * 40 + min(1, magnitude / 35) * 40 + min(1, share / 0.3) * 20
        return Int(raw.rounded())
    }

    /// How far you came down from where you started, and how steady you stayed there.
    static func calmScore(samples: [Sample], baseline: Double, settings: Settings) -> Int {
        let lows = samples.compactMap { s -> Double? in
            let w = samples.filter { abs($0.t - s.t) <= 90 }
            return w.count >= 2 ? median(w.map(\.bpm)) : nil
        }
        guard let lowest = lows.min() else { return 0 }
        let drop = max(0, baseline - lowest)
        let secondHalf = samples.filter { $0.t >= (samples.last?.t ?? 0) / 2 }.map(\.bpm)
        let stability = 1 - min(1, standardDeviation(secondHalf) / 8)
        return Int(min(100, drop / 15 * 70 + stability * 30).rounded())
    }

    // MARK: - Ranking

    struct Ranked: Equatable {
        var id: String
        var score: Int
        var biggest: Double
    }

    /// Scariest first (or calmest, for calm sessions): score, then the biggest jump.
    static func rank(_ items: [Ranked]) -> [String] {
        items.sorted { $0.score == $1.score ? $0.biggest > $1.biggest : $0.score > $1.score }.map(\.id)
    }

    // MARK: - Formatting

    /// 4350 → "1:12:30", 750 → "12:30"
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Math

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)).squareRoot()
    }
}
