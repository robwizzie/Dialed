//
//  VoiceParser.swift
//  Dialed
//
//  Turns a free-form transcript ("I had 16 ounces of water", "mood 4",
//  "300 calories breakfast") into a ContextEvent. Deliberately rules-
//  based — on-device LLM inference belongs in a later phase. Returns
//  nil when no pattern matched so the UI can fall back to a manual
//  kind picker.
//
//  Pure / side-effect-free. Doesn't touch SwiftData — the caller wires
//  the resulting ContextEvent into a ModelContext.
//

import Foundation

enum VoiceParser {

    /// Best-effort parse. Order matters — more specific patterns first so
    /// "16 oz of water" doesn't match a generic number-only fallback.
    static func parse(_ raw: String, at time: Date = Date()) -> ContextEvent? {
        let text = normalize(raw)
        guard !text.isEmpty else { return nil }

        if let event = parseWater(text, at: time) { return event }
        if let event = parseCaffeine(text, at: time) { return event }
        if let event = parseAlcohol(text, at: time) { return event }
        if let event = parseMeal(text, at: time) { return event }
        if let event = parseMood(text, at: time) { return event }
        if let event = parseEnergy(text, at: time) { return event }
        if let event = parseWorkout(text, at: time) { return event }

        // Falls through to a generic note if no pattern matched. The caller
        // can decide whether to surface a kind picker first.
        return ContextEvent(timestamp: time, kind: .note, text: raw.trimmingCharacters(in: .whitespacesAndNewlines), source: .voice)
    }

    // MARK: - Per-kind matchers

    static func parseWater(_ text: String, at time: Date) -> ContextEvent? {
        // "16 oz water", "16 ounces of water", "drank 8 ounces"
        guard text.contains("water")
            || text.contains("ounce") || text.contains(" oz")
            || text.hasSuffix("oz") else { return nil }
        if !text.contains("water")
            && !text.contains("ounce")
            && !text.contains(" oz") && !text.hasSuffix("oz") {
            return nil
        }
        // Only treat as water if the keyword "water" appears OR the unit
        // appears alongside a verb cluster ("drink", "had").
        let isWaterish = text.contains("water")
            || ((text.contains("oz") || text.contains("ounce"))
                && (text.contains("drink") || text.contains("drank") || text.contains("had") || text.contains("log")))
        guard isWaterish else { return nil }
        let oz = firstNumber(in: text) ?? 8
        return ContextEvent(
            timestamp: time, kind: .water, value: oz,
            unit: "oz", source: .voice
        )
    }

    static func parseCaffeine(_ text: String, at time: Date) -> ContextEvent? {
        guard text.contains("caffeine")
            || text.contains("coffee")
            || text.contains("espresso")
            || text.contains("preworkout") || text.contains("pre workout") || text.contains("pre-workout") else {
            return nil
        }
        let mg = firstNumber(in: text)
        let subtype: String? = {
            if text.contains("espresso") { return "espresso" }
            if text.contains("pre") { return "preworkout" }
            if text.contains("coffee") { return "coffee" }
            return "coffee"
        }()
        return ContextEvent(
            timestamp: time, kind: .caffeine, subtype: subtype,
            value: mg ?? 95,
            unit: "mg", source: .voice
        )
    }

    static func parseAlcohol(_ text: String, at time: Date) -> ContextEvent? {
        let triggers = ["beer", "wine", "drink", "drinks", "cocktail", "whiskey", "vodka", "tequila"]
        guard triggers.contains(where: { text.contains($0) }) else { return nil }
        // Ignore "drank water"-style false positives.
        if text.contains("water") { return nil }
        let drinks = firstNumber(in: text) ?? 1
        return ContextEvent(
            timestamp: time, kind: .alcohol, value: drinks,
            unit: "drinks", source: .voice
        )
    }

    static func parseMeal(_ text: String, at time: Date) -> ContextEvent? {
        let mealWords = ["meal", "breakfast", "lunch", "dinner", "snack", "ate", "eating"]
        let hasMealWord = mealWords.contains { text.contains($0) }
        let calories: Double? = numberPreceding(
            keywords: ["cal", "calorie", "calories", "kcal"],
            in: text
        )
        let protein: Double? = numberPreceding(
            keywords: ["protein", "grams of protein", "g protein"],
            in: text
        )
        guard hasMealWord || calories != nil || protein != nil else { return nil }
        let subtype: String? = {
            if text.contains("breakfast") { return "breakfast" }
            if text.contains("lunch")     { return "lunch" }
            if text.contains("dinner")    { return "dinner" }
            if text.contains("snack")     { return "snack" }
            return nil
        }()
        return ContextEvent(
            timestamp: time,
            kind: .meal,
            subtype: subtype,
            value: calories,
            secondaryValue: protein,
            unit: "kcal",
            source: .voice
        )
    }

    static func parseMood(_ text: String, at time: Date) -> ContextEvent? {
        guard text.contains("mood") || text.contains("feeling") else { return nil }
        let rating = clampRating(firstNumber(in: text)) ?? 3
        return ContextEvent(
            timestamp: time, kind: .mood,
            value: Double(rating), source: .voice
        )
    }

    static func parseEnergy(_ text: String, at time: Date) -> ContextEvent? {
        guard text.contains("energy") else { return nil }
        let rating = clampRating(firstNumber(in: text)) ?? 3
        return ContextEvent(
            timestamp: time, kind: .energy,
            value: Double(rating), source: .voice
        )
    }

    static func parseWorkout(_ text: String, at time: Date) -> ContextEvent? {
        let workoutWords = [
            "workout", "lift", "lifted", "trained", "training",
            "push day", "pull day", "leg day", "ran", "running", "cardio"
        ]
        guard workoutWords.contains(where: { text.contains($0) }) else { return nil }
        let subtype: String? = {
            if text.contains("push") { return "push" }
            if text.contains("pull") { return "pull" }
            if text.contains("leg")  { return "legs" }
            if text.contains("cardio") || text.contains("ran") || text.contains("running") { return "cardio" }
            return nil
        }()
        let minutes = numberPreceding(keywords: ["minute", "minutes", " min", " mins"], in: text)
            ?? firstNumber(in: text)
        return ContextEvent(
            timestamp: time, kind: .workout, subtype: subtype,
            value: minutes,
            unit: "min", source: .voice
        )
    }

    // MARK: - Helpers

    static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstNumber(in text: String) -> Double? {
        let pattern = #"-?\d+(\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        guard let range = match?.range, range.location != NSNotFound else { return nil }
        return Double(ns.substring(with: range))
    }

    /// Find a number that appears immediately before (within ~4 words) one
    /// of the supplied keywords. Used to disambiguate "300 calories" from
    /// "30g protein" when both appear in the same utterance.
    static func numberPreceding(keywords: [String], in text: String) -> Double? {
        for keyword in keywords {
            guard let kwRange = text.range(of: keyword) else { continue }
            let prefix = String(text[..<kwRange.lowerBound])
            // Use the LAST number in the prefix — most recent before keyword.
            let pattern = #"-?\d+(\.\d+)?"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = prefix as NSString
            let matches = regex.matches(in: prefix, range: NSRange(location: 0, length: ns.length))
            if let last = matches.last {
                return Double(ns.substring(with: last.range))
            }
        }
        return nil
    }

    private static func clampRating(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return max(1, min(5, Int(value.rounded())))
    }
}
