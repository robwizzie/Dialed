//
//  WorkoutNarrative.swift
//  Dialed
//
//  Reads a workout the way you'd text it to a friend:
//
//    "Today I did flat bench press, 1 set of 10 for 135lbs, 1 set of 10
//     for 145lbs, and 1 set of 8 for 155lbs. Then we did 3 sets of the
//     chest workout where you pull the two sides together … 3 sets of 10
//     of 100lbs and then we finished with incline bench, 1 set of 10 with
//     90lbs … We worked out from 6:15-6:45 (I ran a mile on 5 speed from
//     6-6:15)."
//
//  → Bench press 135×10, 145×10, 155×8 · Pec deck fly 3 × 100×10 ·
//    Incline bench press 90×10, 110×10, 140×6 · lifting 6:15–6:45 PM ·
//    run 1 mi in 15 min at 5 mph, 6:00–6:15 PM.
//
//  Short gym shorthand ("bench 185x8x4") still goes through
//  WorkoutTextParser; this handles sentences, times and cardio. Pure
//  Foundation, tested.
//

import Foundation

enum WorkoutNarrative {

    struct Cardio: Equatable {
        var kind: String            // "Run", "Walk", "Bike", "Row", "Elliptical"
        var miles: Double?
        var minutes: Double?
        var speedMph: Double?
        var start: Date?
        var end: Date?
    }

    struct Reading: Equatable {
        var exercises: [WorkoutTextParser.ParsedExercise]
        var cardio: [Cardio]
        var start: Date?
        var end: Date?

        var minutes: Double? {
            guard let start, let end, end > start else { return nil }
            return end.timeIntervalSince(start) / 60
        }
        var isEmpty: Bool { exercises.isEmpty && cardio.isEmpty && start == nil }
    }

    // MARK: - Read

    static func read(_ raw: String, known: [String] = [], now: Date = Date(), calendar: Calendar = .current) -> Reading {
        var text = normalize(raw)

        // 1. Time ranges — the cardio's (near "ran"/"treadmill") or the session's.
        var sessionStart: Date?, sessionEnd: Date?
        var cardioTimes: [(Date, Date)] = []
        for m in matches(timeRange, in: text).reversed() {
            // "10-12 reps" isn't a time: needs a colon, am/pm or "from".
            let g = m.groups
            let looksLikeTime = !(g[1] + g[4] + g[2] + g[5]).isEmpty || text.dropFirst(m.range.lowerBound).hasPrefix("from")
            guard looksLikeTime, let (s, e) = interval(g, now: now, calendar: calendar) else { continue }
            let before = String(text[text.index(text.startIndex, offsetBy: max(0, m.range.lowerBound - 45))..<text.index(text.startIndex, offsetBy: m.range.lowerBound)])
            if cardioWords.contains(where: before.contains) { cardioTimes.insert((s, e), at: 0) }
            else { sessionStart = s; sessionEnd = e }
            text = replacing(m.range, in: text, with: " ")
        }

        // 2. Cardio: "ran a mile on 5 speed", "walked 2 miles", "bike 20 min".
        var cardio: [Cardio] = []
        for m in matches(cardioClause, in: text).reversed() {
            let clause = m.groups[0]
            var c = Cardio(kind: cardioKind(clause))
            if let d = first(#"(\d+(?:\.\d+)?)\s*(?:mi|mile|miles)\b"#, in: clause) { c.miles = Double(d[0]) }
            if let d = first(#"(\d+(?:\.\d+)?)\s*(?:km|k)\b"#, in: clause), let km = Double(d[0]) { c.miles = km * 0.621 }
            if let d = first(#"(\d+(?:\.\d+)?)\s*(?:min|mins|minutes)\b"#, in: clause) { c.minutes = Double(d[0]) }
            if let d = first(#"(?:speed|pace|at|on)\s*(?:of\s*)?(\d+(?:\.\d+)?)\s*(?:mph|speed)?|(\d+(?:\.\d+)?)\s*(?:mph|speed)"#, in: clause) {
                c.speedMph = Double(d[0].isEmpty ? d[1] : d[0])
            }
            cardio.insert(c, at: 0)
            text = replacing(m.range, in: text, with: " . ")
        }
        for (i, t) in cardioTimes.enumerated() {
            if i < cardio.count {
                cardio[i].start = t.0
                cardio[i].end = t.1
                if cardio[i].minutes == nil { cardio[i].minutes = t.1.timeIntervalSince(t.0) / 60 }
            } else {
                cardio.append(Cardio(kind: "Cardio", minutes: t.1.timeIntervalSince(t.0) / 60, start: t.0, end: t.1))
            }
        }
        for i in cardio.indices where cardio[i].miles == nil {
            if let mph = cardio[i].speedMph, let min = cardio[i].minutes { cardio[i].miles = (mph * min / 60 * 100).rounded() / 100 }
        }

        // 3. Lifting: walk the clauses; a clause naming an exercise starts
        //    one, clauses with sets add to the current one.
        var exercises: [WorkoutTextParser.ParsedExercise] = []
        var current: Int?
        for clause in clauses(text) {
            let sets = setsIn(clause)
            let name = exerciseName(in: clause)
            if let name {
                let canonical = WorkoutTextParser.canonical(name, known: known)
                if let i = exercises.firstIndex(where: { $0.name == canonical }) {
                    current = i
                } else {
                    exercises.append(.init(name: canonical, sets: []))
                    current = exercises.count - 1
                }
            }
            if !sets.isEmpty, let i = current {
                exercises[i].sets += sets
            }
        }
        exercises = exercises.filter { !$0.sets.isEmpty || $0.minutes != nil }

        return Reading(exercises: exercises, cardio: cardio, start: sessionStart, end: sessionEnd)
    }

    // MARK: - Pieces

    private static let numberWords: [(String, String)] = [
        ("twenty", "20"), ("fifteen", "15"), ("twelve", "12"), ("eleven", "11"), ("ten", "10"),
        ("nine", "9"), ("eight", "8"), ("seven", "7"), ("six", "6"), ("five", "5"), ("four", "4"),
        ("three", "3"), ("two", "2"), ("one", "1"), ("a single", "1"), ("a couple of", "2")
    ]

    static func normalize(_ raw: String) -> String {
        var s = " " + raw.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-") + " "
        for (word, digit) in numberWords {
            s = s.replacingOccurrences(of: " \(word) ", with: " \(digit) ")
        }
        s = replace(#"\ba (set|mile|minute)\b"#, in: s, with: "1 $1")
        s = replace(#"(\d)\s*(?:lbs|lb|pounds|pound|#)\b"#, in: s, with: "$1 lb")
        s = replace(#"\s+"#, in: s, with: " ")
        return s
    }

    // "6:15-6:45", "from 6-6:15", "6:15 to 6:45 pm"
    private static let timeRange = #"(?:from\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|to|until|till)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#

    private static let cardioWords = ["ran", "run", "jog", "treadmill", "walk", "bike", "biked", "cycl", "row", "elliptical", "stair", "mile", "cardio"]

    // A cardio clause up to the next sentence break or bracket.
    private static let cardioClause = #"((?:i\s+)?(?:ran|run|jogged|jog|walked|walk|biked|bike|cycled|rowed|did\s+the\s+treadmill|treadmill|elliptical|stairmaster|stair\s+climber)\b(?:[^.;()\n]|\.(?=\d))*)"#

    private static func cardioKind(_ clause: String) -> String {
        if clause.contains("walk") { return "Walk" }
        if clause.contains("bike") || clause.contains("cycl") { return "Bike" }
        if clause.contains("row") { return "Row" }
        if clause.contains("elliptical") { return "Elliptical" }
        if clause.contains("stair") { return "Stairs" }
        return "Run"
    }

    /// Sentences and clauses: ".", ",", ";", "and then", "then", "finished with"…
    static func clauses(_ text: String) -> [String] {
        var s = text
        for sep in [" and then ", " then ", " after that ", " followed by ", " finished with ", " finished off with ",
                    " next ", " we finished ", " and finished ", " plus "] {
            s = s.replacingOccurrences(of: sep, with: " | ")
        }
        // "… 145 lb, and 1 set of 8 …" — " and " between set phrases splits too.
        s = s.replacingOccurrences(of: " and ", with: " | ")
        return s.split(whereSeparator: { ".,;|()\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Every set described in a clause.
    static func setsIn(_ clause: String) -> [WorkoutTextParser.ParsedSet] {
        let c = " " + clause + " "
        // 3 sets of 10 for/with/at/of 100 lb  ·  3 sets of 10 reps @ 100
        if let m = first(#"(\d+)\s*sets?\s*(?:of\s*)?(\d+)(?:\s*-\s*\d+)?\s*(?:reps?\s*)?(?:for|with|at|of|@)\s*(\d+(?:\.\d+)?)"#, in: c),
           let n = Int(m[0]), let r = Int(m[1]), let w = Double(m[2]) {
            return Array(repeating: .init(weight: w, reps: r), count: max(1, min(12, n)))
        }
        // 3 sets of 10 (bodyweight)
        if let m = first(#"(\d+)\s*sets?\s*of\s*(\d+)\b(?!\s*lb)"#, in: c), let n = Int(m[0]), let r = Int(m[1]) {
            let weight = first(#"(\d+(?:\.\d+)?)\s*lb"#, in: c).flatMap { Double($0[0]) }
            return Array(repeating: .init(weight: weight, reps: r), count: max(1, min(12, n)))
        }
        // 10 reps at 135  ·  10 reps with 90 lb
        if let m = first(#"(\d+)\s*reps?\s*(?:for|with|at|of|@)\s*(\d+(?:\.\d+)?)"#, in: c), let r = Int(m[0]), let w = Double(m[1]) {
            return [.init(weight: w, reps: r)]
        }
        // 135 lb for 10  ·  135 for 10 reps
        if let m = first(#"(\d+(?:\.\d+)?)\s*(?:lb\s*)?(?:for|x)\s*(\d+)\b"#, in: c), let w = Double(m[0]), let r = Int(m[1]), w > 12 {
            return [.init(weight: w, reps: r)]
        }
        // "10 pushups", "15 reps" — one bodyweight set
        if let m = first(#"^\s*(\d+)\s+(?:reps?\b|[a-z])"#, in: clause), let r = Int(m[0]), r <= 100,
           clause.range(of: #"\d+[^\d]+\d"#, options: .regularExpression) == nil {
            return [.init(weight: nil, reps: r)]
        }
                // Shorthand inside a sentence: "135x10", "3x10 @ 100"
        if let shorthand = WorkoutTextParser.parseSegment("x " + clause), !shorthand.sets.isEmpty,
           clause.range(of: #"\d+\s*x\s*\d+"#, options: .regularExpression) != nil {
            return shorthand.sets
        }
        return []
    }

    // MARK: - Names

    /// Words that mean "this clause names an exercise".
    private static let lexicon = [
        "bench", "press", "fly", "flye", "flies", "pec", "chest", "squat", "deadlift", "rdl", "row", "pulldown",
        "pull-up", "pullup", "pull up", "chin", "curl", "extension", "pushdown", "dip", "lunge", "raise", "shrug",
        "crunch", "plank", "calf", "leg", "hip thrust", "kickback", "crossover", "push-up", "pushup", "push up",
        "face pull", "skull", "tricep", "bicep", "shoulder", "lat", "glute", "hamstring", "quad", "ab ", "abs",
        "thruster", "swing", "clean", "snatch", "carry", "woodchop", "step-up", "step up"
    ]

    /// Described, not named: what people say → the exercise.
    private static let descriptions: [(all: [String], name: String)] = [
        (["pull", "together"], "Pec deck fly"), (["inner chest"], "Pec deck fly"), (["pec deck"], "Pec deck fly"),
        (["butterfly"], "Pec deck fly"), (["chest fly"], "Pec deck fly"), (["squeeze", "chest"], "Pec deck fly"),
        (["cable", "crossover"], "Cable fly"), (["pull", "down", "bar"], "Cable lat pulldown"),
        (["sit", "push", "weight", "legs"], "Leg press"), (["leg press"], "Leg press"),
        (["leg extension"], "Leg extension"), (["leg curl"], "Leg curl"), (["hamstring curl"], "Leg curl"),
        (["lateral raise"], "Lateral raise"), (["side raise"], "Lateral raise"), (["shoulder raise"], "Lateral raise"),
        (["skull crusher"], "Skull crusher"), (["rope", "tricep"], "Rope pushdown"), (["tricep pushdown"], "Rope pushdown"),
        (["hammer curl"], "Hammer curl"), (["preacher"], "Preacher curl"), (["hip thrust"], "Hip thrust"),
        (["calf raise"], "Calf raise"), (["seated row"], "Cable row"), (["shrug"], "Shrug")
    ]

    /// Fillers that wrap a name ("today I did", "then we did 3 sets of the").
    private static let fillers = [
        "today", "i did", "we did", "did", "then", "we", "i", "the", "a", "an", "of", "some", "workout", "exercise",
        "machine", "finished with", "started with", "went with", "on", "with", "for", "and", "that was",
        "sets", "set", "reps", "rep", "to", "where you", "you", "my", "our", "flat", "at", "@", "in", "x", "lb", "each"
    ]

    static func exerciseName(in clause: String) -> String? {
        let c = " " + clause + " "
        for d in descriptions where d.all.allSatisfy({ c.contains($0) }) { return d.name }
        guard lexicon.contains(where: { c.contains(" " + $0) || c.contains($0 + " ") }) else { return nil }
        // Strip set phrases, numbers and fillers; keep the words around the lexicon word.
        var s = replace(#"\d+(?:\.\d+)?\s*(?:lb|sets?|reps?|x\s*\d+)?"#, in: c, with: " ")
        for f in fillers.sorted(by: { $0.count > $1.count }) {
            s = s.replacingOccurrences(of: " \(f) ", with: " ")
            s = s.replacingOccurrences(of: " \(f) ", with: " ")
        }
        let words = s.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 6 else { return nil }
        let name = words.joined(separator: " ")
        // "incline bench" → "incline bench press"
        if name.hasSuffix("bench") { return name + " press" }
        return name
    }

    // MARK: - Times

    /// Hours on a 12-hour clock become the most recent matching time today
    /// (so "6:15-6:45" at 8 PM is this evening, at 9 AM this morning).
    private static func interval(_ g: [String], now: Date, calendar: Calendar) -> (Date, Date)? {
        guard let h1 = Int(g[0]), let h2 = Int(g[3]), (1...23).contains(h1), (1...23).contains(h2) else { return nil }
        let m1 = Int(g[1]) ?? 0, m2 = Int(g[4]) ?? 0
        guard m1 < 60, m2 < 60 else { return nil }
        let endMeridiem = g[5].isEmpty ? nil : g[5]
        let startMeridiem = g[2].isEmpty ? endMeridiem : g[2]
        let day = calendar.startOfDay(for: now)

        func clock(_ h: Int, _ m: Int, _ meridiem: String?) -> [Date] {
            var hours: [Int]
            if let meridiem { hours = [h % 12 + (meridiem == "pm" ? 12 : 0)] }
            else if h > 12 { hours = [h] }
            else { hours = [h % 12, h % 12 + 12] }
            return hours.compactMap { calendar.date(bySettingHour: $0, minute: m, second: 0, of: day) }
        }
        let grace = now.addingTimeInterval(15 * 60)
        let ends = clock(h2, m2, endMeridiem).filter { $0 <= grace }
        guard let end = ends.max() ?? clock(h2, m2, endMeridiem).min() else { return nil }
        let starts = clock(h1, m1, startMeridiem).filter { $0 < end && end.timeIntervalSince($0) <= 5 * 3600 }
        guard let start = starts.max() else { return nil }
        return (start, end)
    }

    // MARK: - Regex helpers

    private struct Match { let range: Range<Int>; let groups: [String] }

    private static func matches(_ pattern: String, in s: String) -> [Match] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            let groups = (1..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            // Character offsets (the text is ASCII after normalize for these patterns).
            let lower = s.distance(from: s.startIndex, to: String.Index(utf16Offset: m.range.location, in: s))
            let upper = s.distance(from: s.startIndex, to: String.Index(utf16Offset: m.range.location + m.range.length, in: s))
            return Match(range: lower..<upper, groups: groups)
        }
    }

    private static func replacing(_ range: Range<Int>, in s: String, with r: String) -> String {
        let a = s.index(s.startIndex, offsetBy: range.lowerBound), b = s.index(s.startIndex, offsetBy: range.upperBound)
        return s.replacingCharacters(in: a..<b, with: r)
    }

    private static func first(_ pattern: String, in s: String) -> [String]? {
        matches(pattern, in: s).first?.groups
    }

    private static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }
}
