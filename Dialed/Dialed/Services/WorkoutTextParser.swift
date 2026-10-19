//
//  WorkoutTextParser.swift
//  Dialed
//
//  Turns what you type at the gym into sets:
//
//    "bench 185x8x4, squat 225 5x5, lat pulldown 120 3x10"
//    "rdl 3x8 @ 155; curls 30s 3x12; plank 60s; bike 20 min"
//    "bench 135x10, 155x8, 175x6"      (one exercise, three sets)
//    "incline db 60 for 10, 9, 8"      (reps per set)
//    "pushups 3x15"                    (bodyweight)
//
//  Names are matched to your plan's exercises ("bench" → "Bench press",
//  "rdl" → "Barbell Romanian deadlift") so the sets land on the right
//  row and count toward progress. Pure Foundation, tested.
//

import Foundation

enum WorkoutTextParser {

    struct ParsedSet: Equatable {
        var weight: Double?
        var reps: Int
    }

    struct ParsedExercise: Equatable {
        var name: String
        var sets: [ParsedSet]
        var minutes: Double?
        var miles: Double?
    }

    /// Short names people type → words that appear in the plan's names.
    static let aliases: [String: String] = [
        "bp": "bench press", "bench": "bench press", "flat bench": "bench press",
        "squat": "barbell back squat", "squats": "barbell back squat", "back squat": "barbell back squat",
        "rdl": "barbell romanian deadlift", "rdls": "barbell romanian deadlift", "romanian deadlift": "barbell romanian deadlift",
        "pulldown": "cable lat pulldown", "pulldowns": "cable lat pulldown", "lat pulldown": "cable lat pulldown",
        "lat pull": "cable lat pulldown", "lats": "cable lat pulldown",
        "db row": "one-arm dumbbell row", "dumbbell row": "one-arm dumbbell row", "rows": "row",
        "seated row": "cable row",
        "face pull": "cable face pull", "face pulls": "cable face pull",
        "fly": "cable fly", "flys": "cable fly", "flies": "cable fly", "cable flies": "cable fly",
        "ohp": "dumbbell shoulder press", "shoulder press": "dumbbell shoulder press", "overhead press": "dumbbell shoulder press",
        "lunge": "dumbbell walking lunge", "lunges": "dumbbell walking lunge", "walking lunges": "dumbbell walking lunge",
        "goblet": "dumbbell goblet squat", "goblet squats": "dumbbell goblet squat",
        "thrusters": "dumbbell thruster", "thruster": "dumbbell thruster",
        "pushups": "push-up", "push ups": "push-up", "pushup": "push-up",
        "swings": "kettlebell / dumbbell swing", "kb swings": "kettlebell / dumbbell swing",
        "curls": "curl", "bicep curls": "curl", "pushdowns": "rope pushdown", "tricep pushdowns": "rope pushdown",
        "db": "dumbbell", "bb": "barbell", "kb": "kettlebell"
    ]

    // MARK: - Parse

    /// Parse free text into exercises. `known` are names to match against
    /// (today's session first); unmatched names are tidied and kept.
    static func parse(_ text: String, known: [String] = []) -> [ParsedExercise] {
        var out: [ParsedExercise] = []
        for segment in segments(text) {
            guard var ex = parseSegment(segment) else { continue }
            ex.name = canonical(ex.name, known: known)
            // A second line for the same exercise adds sets.
            if let i = out.firstIndex(where: { $0.name == ex.name }), !ex.sets.isEmpty {
                out[i].sets += ex.sets
            } else {
                out.append(ex)
            }
        }
        return out
    }

    /// Lines, ";" and commas that start a new exercise ("…x4, squat …"),
    /// but not commas inside a list of numbers ("for 8, 8, 7").
    static func segments(_ text: String) -> [String] {
        var parts: [String] = []
        for line in text.replacingOccurrences(of: ";", with: "\n").components(separatedBy: .newlines) {
            var current = ""
            let chars = Array(line)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == "," {
                    var j = i + 1
                    while j < chars.count, chars[j] == " " { j += 1 }
                    if j < chars.count, chars[j].isLetter, !startsWithUnit(chars, at: j) {
                        parts.append(current)
                        current = ""
                        i = j
                        continue
                    }
                }
                current.append(c)
                i += 1
            }
            parts.append(current)
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func startsWithUnit(_ chars: [Character], at j: Int) -> Bool {
        let rest = String(chars[j...]).lowercased()
        return ["lb", "lbs", "reps", "rep", "x "].contains { rest.hasPrefix($0) }
    }

    static func parseSegment(_ raw: String) -> ParsedExercise? {
        var s = raw.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "*", with: "x")
        // Split the name (leading words) from the numbers.
        guard let firstDigit = s.firstIndex(where: { $0.isNumber }) else {
            let name = s.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : ParsedExercise(name: name, sets: [])
        }
        var name = String(s[..<firstDigit]).trimmingCharacters(in: .whitespaces)
        for suffix in [" @", " at", " for", ":", "-", " with"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty else { return nil }
        s = String(s[firstDigit...])

        // Cardio / timed work.
        var minutes: Double?
        var miles: Double?
        if let m = first(#"(\d+(?:\.\d+)?)\s*(?:mi|mile|miles)\b"#, in: s) { miles = Double(m[0]) }
        if let m = first(#"(\d+(?:\.\d+)?)\s*(?:min|mins|minute|minutes)\b"#, in: s) { minutes = Double(m[0]) }
        if let m = first(#"(\d+)\s*(?:s|sec|secs|seconds)\b"#, in: s), !s.contains("x") { minutes = (Double(m[0]) ?? 0) / 60 }
        if miles != nil || minutes != nil, !s.contains("x") {
            return ParsedExercise(name: name, sets: [], minutes: minutes, miles: miles)
        }

        // Tidy units: "185 lbs" → "185", "30s 3x12" (dumbbells) → "30 3x12",
        // "3 sets of 12" → "3x12", "x 8 reps" → "x8".
        s = replace(#"(\d)\s*(?:lbs|lb|#|kg)\b"#, in: s, with: "$1")
        s = replace(#"(\d)s\b"#, in: s, with: "$1")
        s = replace(#"(\d+)\s*sets?\s*(?:of|x)\s*(\d+)"#, in: s, with: "$1x$2")
        s = replace(#"\s*reps?\b"#, in: s, with: "")
        s = replace(#"\s*x\s*"#, in: s, with: "x")

        var sets: [ParsedSet] = []
        if let m = first(#"(\d+(?:\.\d+)?)x(\d+)x(\d+)"#, in: s),
           let a = Double(m[0]), let b = Int(m[1]), let c = Double(m[2]) {
            // 185x8x4 = weight × reps × sets; 4x8x185 = sets × reps × weight.
            if a > 25 { sets = repeatSet(ParsedSet(weight: a, reps: b), Int(c)) }
            else { sets = repeatSet(ParsedSet(weight: c, reps: b), Int(a)) }
        } else if let m = first(#"(\d+)x(\d+)\s*(?:@|at)\s*(\d+(?:\.\d+)?)"#, in: s),
                  let n = Int(m[0]), let r = Int(m[1]), let w = Double(m[2]) {
            sets = repeatSet(ParsedSet(weight: w, reps: r), n)                       // 3x8 @ 155
        } else if let m = first(#"(\d+(?:\.\d+)?)\s+(\d+)x(\d+)"#, in: s),
                  let w = Double(m[0]), w > 12, let n = Int(m[1]), let r = Int(m[2]) {
            sets = repeatSet(ParsedSet(weight: w, reps: r), n)                       // 225 5x5
        } else if let m = first(#"(\d+)x(\d+)\s+(\d+(?:\.\d+)?)"#, in: s),
                  let n = Int(m[0]), let r = Int(m[1]), let w = Double(m[2]) {
            sets = repeatSet(ParsedSet(weight: w, reps: r), n)                       // 5x5 225
        } else if let m = first(#"(\d+(?:\.\d+)?)\s*(?:for|:)\s*([\d,\s/]+)"#, in: s), let w = Double(m[0]) {
            let reps = m[1].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).compactMap { Int($0) }
            sets = reps.map { ParsedSet(weight: w, reps: $0) }                       // 60 for 10, 9, 8
        } else {
            let pairs = all(#"(\d+(?:\.\d+)?)x(\d+)"#, in: s)
            let weighted = pairs.compactMap { p -> ParsedSet? in
                guard let w = Double(p[0]), let r = Int(p[1]) else { return nil }
                return ParsedSet(weight: w, reps: r)
            }
            if weighted.count == 1, let only = weighted.first, (only.weight ?? 0) <= 12 {
                sets = repeatSet(ParsedSet(weight: nil, reps: only.reps), Int(only.weight ?? 1)) // 3x15
            } else {
                sets = weighted                                                      // 135x10, 155x8
            }
        }
        sets = sets.filter { $0.reps > 0 && $0.reps <= 100 && ($0.weight ?? 0) <= 1_500 }
        guard !sets.isEmpty else { return nil }
        return ParsedExercise(name: name, sets: Array(sets.prefix(12)))
    }

    // MARK: - Names

    /// Match a typed name to the closest known exercise; else tidy it.
    static func canonical(_ typed: String, known: [String]) -> String {
        var name = typed.lowercased().trimmingCharacters(in: .whitespaces)
        if let full = aliases[name] {
            name = full
        } else {
            name = name.split(separator: " ").map { aliases[String($0)] ?? String($0) }.joined(separator: " ")
        }
        let tokens = Set(tokenize(name))
        // Equipment words alone ("dumbbell") don't make a match.
        let specific = tokens.subtracting(generic)
        var best: (String, Double)?
        for k in known {
            let kt = Set(tokenize(k))
            let sharedSpecific = specific.intersection(kt).count
            guard sharedSpecific > 0 else { continue }
            let shared = Double(tokens.intersection(kt).count)
            let score = shared / Double(tokens.count) + Double(sharedSpecific) / Double(max(kt.count, 1)) * 0.25
            if score > (best?.1 ?? 0) { best = (k, score) }
        }
        if let best, best.1 >= 0.6 { return best.0 }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static let generic: Set<String> = ["dumbbell", "barbell", "cable", "kettlebell", "machine", "one-arm", "arm", "incline", "decline", "seated", "standing"]

    private static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { " ()/+-,".contains($0) })
            .map { stem(String($0)) }
    }

    private static func stem(_ w: String) -> String {
        w.count > 3 && w.hasSuffix("s") ? String(w.dropLast()) : w
    }

    // MARK: - Regex helpers

    private static func repeatSet(_ set: ParsedSet, _ count: Int) -> [ParsedSet] {
        Array(repeating: set, count: max(1, min(12, count)))
    }

    private static func first(_ pattern: String, in s: String) -> [String]? {
        all(pattern, in: s).first
    }

    private static func all(_ pattern: String, in s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    private static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }
}
