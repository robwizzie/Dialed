//
//  MealMath.swift
//  Dialed
//
//  Turns "broccoli with olive oil, salt, pepper and Mike's hot honey" or
//  "5 pieces of sushi roll" into an itemized estimate: each food, how
//  much, and its calories and macros from NutritionTable. Amounts you
//  give are used ("8 oz chicken", "2 tbsp ranch", "half an avocado");
//  otherwise a typical portion. Pure Foundation, tested.
//

import Foundation

struct MealPart: Equatable, Identifiable {
    var name: String
    /// "1 cup", "5 pieces", "1 tsp".
    var amount: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// From the table (true) or an estimate for something it doesn't know.
    var fromTable: Bool

    var id: String { name + amount }

    /// The same food at `factor` times the amount.
    func scaled(_ factor: Double) -> MealPart {
        var p = self
        p.grams *= factor
        p.calories *= factor
        p.protein *= factor
        p.carbs *= factor
        p.fat *= factor
        p.amount = MealMath.scaledAmount(amount, factor)
        return p
    }
}

enum MealMath {

    struct Result: Equatable {
        var parts: [MealPart]
        /// Pieces of the description it couldn't match to a food.
        var unknown: [String]

        var calories: Double { parts.reduce(0) { $0 + $1.calories } }
        var protein: Double { parts.reduce(0) { $0 + $1.protein } }
        var carbs: Double { parts.reduce(0) { $0 + $1.carbs } }
        var fat: Double { parts.reduce(0) { $0 + $1.fat } }
        var isComplete: Bool { unknown.isEmpty && !parts.isEmpty }
    }

    /// Itemize a plain-language meal.
    static func estimate(_ text: String) -> Result {
        var parts: [MealPart] = []
        var unknown: [String] = []
        for chunk in chunks(text) {
            let q = quantity(chunk)
            guard let food = NutritionTable.match(q.rest) ?? NutritionTable.match(chunk) else {
                if !meaningful(q.rest).isEmpty { unknown.append(chunk) }
                continue
            }
            // "chipotle bowl double chicken": the chicken is known, the dish
            // isn't — keep the chicken but flag the rest so a smarter pass runs.
            if !meaningful(leftover(q.rest, after: food)).isEmpty { unknown.append(chunk) }
            if var part = part(food, amount: q.amount, unit: q.unit, size: q.size, text: chunk) {
                if let i = parts.firstIndex(where: { $0.name == part.name }) {
                    part = combine(parts[i], part)
                    parts[i] = part
                } else {
                    parts.append(part)
                }
            }
        }
        return Result(parts: parts, unknown: unknown)
    }

    /// Words that describe how it's cooked or served, not what it is.
    private static let filler: Set<String> = [
        "a", "an", "the", "some", "my", "of", "grilled", "baked", "roasted", "steamed", "fried", "sauteed", "sauteed",
        "fresh", "plain", "cooked", "raw", "homemade", "lean", "extra", "light", "sliced", "chopped", "diced", "frozen",
        "hot", "cold", "little", "bit", "side", "drizzle", "splash", "pinch", "dash", "piece", "pieces", "serving",
        "organic", "boneless", "skinless", "small", "medium", "large", "big", "whole", "on", "top", "to", "taste"
    ]

    private static func meaningful(_ text: String) -> [String] {
        NutritionTable.normalize(text).split(separator: " ").map(String.init).filter { !filler.contains($0) }
    }

    /// What's left of `text` once the food's matching alias is removed.
    private static func leftover(_ text: String, after food: FoodFacts) -> String {
        var t = " " + NutritionTable.normalize(text) + " "
        let aliases = ([food.name.lowercased()] + food.aliases).map(NutritionTable.normalize).sorted { $0.count > $1.count }
        for a in aliases where t.contains(" " + a + " ") || t.contains(" " + a + "s ") {
            t = t.replacingOccurrences(of: " " + a + "s ", with: " ").replacingOccurrences(of: " " + a + " ", with: " ")
            break
        }
        return t
    }

    /// One food at an amount (or its usual portion).
    static func part(_ food: FoodFacts, amount: Double?, unit: String?, size: Double = 1, text: String = "") -> MealPart? {
        if food.calories == 0 {
            return MealPart(name: food.name, amount: "to taste", grams: 0, calories: 0, protein: 0, carbs: 0, fat: 0, fromTable: true)
        }
        var useUnit = unit ?? food.defaultMeasure.unit
        var useAmount = amount ?? food.defaultMeasure.amount
        if unit == nil, amount != nil {
            // "a california roll" is the whole roll; "2 chicken breasts" are pieces.
            if food.measures["roll"] != nil, text.contains("roll"), !text.contains("piece") {
                useUnit = "roll"
            } else if ["oz", "cup", "tbsp", "tsp", "g"].contains(food.defaultMeasure.unit), food.measures["piece"] != nil {
                useUnit = "piece"
            } else {
                useUnit = food.defaultMeasure.unit
            }
        }
        if food.grams(useAmount, useUnit) == nil {
            useUnit = food.defaultMeasure.unit
            if amount == nil { useAmount = food.defaultMeasure.amount }
        }
        guard let base = food.grams(useAmount, useUnit) else { return nil }
        let grams = base * size
        let k = grams / 100
        let sizeWord = size < 1 ? "small " : (size > 1 ? "large " : "")
        return MealPart(name: food.name, amount: describe(useAmount, useUnit, size: sizeWord), grams: grams,
                        calories: food.calories * k, protein: food.protein * k,
                        carbs: food.carbs * k, fat: food.fat * k, fromTable: true)
    }

    // MARK: - Reading the text

    /// "broccoli with olive oil, salt, pepper and hot honey" → foods.
    static func chunks(_ text: String) -> [String] {
        var s = " " + text.lowercased() + " "
        for sep in [" with ", " and ", " plus ", " & ", " + ", " w/ ", " topped with ", " on top of ", " on ", " side of "] {
            s = s.replacingOccurrences(of: sep, with: ",")
        }
        return s.split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !["a", "an", "some", "the", "side"].contains($0) }
    }

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "twelve": 12, "half": 0.5, "a half": 0.5, "quarter": 0.25,
        "a couple": 2, "couple": 2, "few": 3, "a few": 3, "dozen": 12
    ]

    private static let units: [String: String] = [
        "g": "g", "gram": "g", "grams": "g", "kg": "kg", "oz": "oz", "ounce": "oz", "ounces": "oz",
        "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb", "ml": "ml",
        "cup": "cup", "cups": "cup", "c": "cup",
        "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbs": "tbsp",
        "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
        "piece": "piece", "pieces": "piece", "pc": "piece", "pcs": "piece",
        "slice": "slice", "slices": "slice", "serving": "serving", "servings": "serving",
        "scoop": "scoop", "scoops": "scoop", "can": "can", "cans": "can", "bottle": "bottle",
        "glass": "glass", "glasses": "glass", "pint": "pint", "handful": "handful", "handfuls": "handful",
        "clove": "clove", "cloves": "clove", "drizzle": "drizzle", "pat": "pat", "pinch": "pinch",
        "bar": "bar", "bag": "bag", "roll": "roll", "rolls": "roll", "head": "head"
    ]

    struct Quantity {
        var amount: Double?
        var unit: String?
        var size: Double = 1
        var rest: String
    }

    /// "cups" → "cup", "Tablespoon" → "tbsp"; nil for anything unknown.
    static func normalizedUnit(_ text: String) -> String? {
        units[text.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    /// Leading amount and unit: "5 pieces of sushi roll" → 5, piece, "sushi roll".
    static func quantity(_ chunk: String) -> Quantity {
        var words = chunk.split(separator: " ").map(String.init)
        var amount: Double?
        if let first = words.first {
            if let n = Double(first) { amount = n; words.removeFirst() }
            else if first.contains("/"), let frac = fraction(first) { amount = frac; words.removeFirst() }
            else if words.count > 1, let n = numberWords[first + " " + words[1]] { amount = n; words.removeFirst(2) }
            else if let n = numberWords[first] { amount = n; words.removeFirst() }
            // "8oz", "100g"
            else if let m = first.range(of: #"^\d+(\.\d+)?"#, options: .regularExpression),
                    let n = Double(first[m]), let u = units[String(first[m.upperBound...])] {
                var rest = Array(words.dropFirst())
                if rest.first == "of" { rest.removeFirst() }
                return Quantity(amount: n, unit: u, rest: rest.joined(separator: " "))
            }
        }
        // "half an avocado"
        if amount == 0.5, words.first == "an" || words.first == "a" { words.removeFirst() }
        var unit: String?
        if let w = words.first, let u = units[w], u != "roll" || words.count == 1 {
            unit = u
            words.removeFirst()
        }
        if words.first == "of" { words.removeFirst() }
        if words.first == "a" || words.first == "an" { words.removeFirst() }
        // Sizes: "large egg", "small banana".
        var size = 1.0
        if let w = words.first, ["small", "medium", "large", "big", "jumbo"].contains(w) {
            words.removeFirst()
            size = w == "small" ? 0.75 : (w == "medium" ? 1 : 1.25)
        }
        let rest = words.joined(separator: " ")
        if unit == "roll" { return Quantity(amount: amount, unit: "roll", size: size, rest: rest.isEmpty ? "sushi roll" : rest) }
        return Quantity(amount: amount, unit: unit, size: size, rest: rest)
    }

    private static func fraction(_ s: String) -> Double? {
        let p = s.split(separator: "/").compactMap { Double($0) }
        return p.count == 2 && p[1] != 0 ? p[0] / p[1] : nil
    }

    // MARK: - Helpers

    static func describe(_ amount: Double, _ unit: String, size: String = "") -> String {
        let fractions: [Double: String] = [0.25: "¼", 0.5: "½", 0.75: "¾", 1.5: "1½", 2.5: "2½"]
        let n = fractions[amount] ?? (amount == amount.rounded() ? String(Int(amount)) : String(format: "%g", (amount * 100).rounded() / 100))
        let plural = amount > 1
        let word: String
        switch unit {
        case "piece", "slice", "cup", "serving", "scoop", "can", "bottle", "roll", "clove", "bar", "pint", "handful":
            word = unit + (plural ? "s" : "")
        case "glass":
            word = plural ? "glasses" : "glass"
        default:
            word = unit
        }
        return "\(n) \(size)\(word)"
    }

    static func scaledAmount(_ text: String, _ factor: Double) -> String {
        let words = text.split(separator: " ")
        let fractions: [String: Double] = ["¼": 0.25, "½": 0.5, "¾": 0.75, "1½": 1.5, "2½": 2.5]
        guard let first = words.first, let n = Double(first) ?? fractions[String(first)] else { return text }
        var unit = words.dropFirst().joined(separator: " ")
        if unit.hasSuffix("es"), unit.hasPrefix("glass") { unit = "glass" }
        else if unit.hasSuffix("s"), unit.count > 3 { unit = String(unit.dropLast()) }
        return describe(n * factor, unit)
    }

    private static func combine(_ a: MealPart, _ b: MealPart) -> MealPart {
        MealPart(name: a.name, amount: a.amount == b.amount && a.calories == 0 ? a.amount : a.amount + " + " + b.amount, grams: a.grams + b.grams,
                 calories: a.calories + b.calories, protein: a.protein + b.protein,
                 carbs: a.carbs + b.carbs, fat: a.fat + b.fat, fromTable: a.fromTable && b.fromTable)
    }

    /// Calories that disagree with the macros (4/4/9) get pulled to them —
    /// a cheap check on numbers that came from a model.
    static func reconciled(calories: Double, protein: Double, carbs: Double, fat: Double) -> Double {
        let fromMacros = protein * 4 + carbs * 4 + fat * 9
        guard fromMacros > 20 else { return calories }
        return abs(calories - fromMacros) / fromMacros > 0.2 ? fromMacros : calories
    }
}
