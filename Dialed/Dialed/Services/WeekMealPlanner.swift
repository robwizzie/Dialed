//
//  WeekMealPlanner.swift
//  Dialed
//
//  A week of simple, high-protein go-to meals that fit your calories and
//  protein. Meals come from a small library of everyday combos (chicken
//  rice bowl, Greek yogurt bowl, turkey chili…) made of NutritionTable
//  foods in grams, so every number is priced by the same table the rest
//  of the app uses. Each day gets a breakfast, lunch, dinner and snack
//  sized to land on your target; the week rotates through your best two
//  or three per slot (favoring foods you already log), any meal can be
//  swapped, and the groceries add up into a shopping list. Pure
//  Foundation, tested.
//

import Foundation

enum WeekMealPlanner {

    // MARK: - Types

    enum Slot: String, Codable, CaseIterable, Identifiable {
        case breakfast, lunch, dinner, snack

        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        /// Share of the day's calories.
        var share: Double {
            switch self {
            case .breakfast: return 0.25
            case .lunch:     return 0.30
            case .dinner:    return 0.32
            case .snack:     return 0.13
            }
        }

        /// Rough time of day, for "next meal".
        var hour: Int {
            switch self {
            case .breakfast: return 7
            case .lunch:     return 12
            case .snack:     return 15
            case .dinner:    return 18
            }
        }
    }

    struct Ingredient: Codable, Equatable {
        /// NutritionTable food name.
        var food: String
        var grams: Double
    }

    struct Template: Equatable {
        let id: String
        let name: String
        let emoji: String
        let slot: Slot
        let ingredients: [Ingredient]
    }

    struct Meal: Codable, Equatable, Identifiable {
        var templateID: String
        var name: String
        var emoji: String
        var slot: Slot
        var ingredients: [Ingredient]
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double

        var id: String { slot.rawValue + "-" + templateID }

        /// "6 oz chicken breast · 1¼ cups white rice · 1 cup broccoli"
        var ingredientLine: String {
            ingredients.filter { $0.grams >= 5 }.map { WeekMealPlanner.amountText($0) }.joined(separator: " · ")
        }
    }

    struct DayPlan: Codable, Equatable {
        var date: Date
        var meals: [Meal]

        var calories: Double { meals.reduce(0) { $0 + $1.calories } }
        var protein: Double { meals.reduce(0) { $0 + $1.protein } }
    }

    struct WeekPlan: Codable, Equatable {
        var start: Date
        var days: [DayPlan]
        var calories: Double
        var protein: Double
        /// Bumped by "Regenerate" to rotate in different meals.
        var seed: Int
    }

    struct GroceryItem: Codable, Equatable, Identifiable {
        var food: String
        var aisle: String
        var amount: String
        var id: String { food }
    }

    // MARK: - Library

    private static func t(_ id: String, _ name: String, _ emoji: String, _ slot: Slot,
                          _ items: [(String, Double)]) -> Template {
        Template(id: id, name: name, emoji: emoji, slot: slot,
                 ingredients: items.map { Ingredient(food: $0.0, grams: $0.1) })
    }

    static let library: [Template] = [
        // Breakfast
        t("yogurt-bowl", "Greek yogurt bowl", "🥣", .breakfast,
          [("Greek yogurt", 250), ("Blueberries", 100), ("Granola", 30), ("Honey", 7)]),
        t("eggs-toast", "Eggs, whites & toast", "🍳", .breakfast,
          [("Egg", 100), ("Egg whites", 160), ("Whole wheat bread", 64), ("Strawberries", 100)]),
        t("protein-oats", "Protein oats", "🥣", .breakfast,
          [("Oatmeal", 50), ("Whey protein", 30), ("Banana", 60), ("Peanut butter", 10)]),
        t("breakfast-burrito", "Breakfast burrito", "🌯", .breakfast,
          [("Egg", 100), ("Egg whites", 160), ("Flour tortilla", 45), ("Cheddar cheese", 20), ("Hot sauce", 15)]),
        // Lunch
        t("chicken-bowl", "Chicken rice bowl", "🍚", .lunch,
          [("Chicken breast", 170), ("White rice", 180), ("Broccoli", 100), ("Soy sauce", 15)]),
        t("turkey-wrap", "Turkey wrap", "🌯", .lunch,
          [("Turkey deli meat", 140), ("Flour tortilla", 45), ("Cheddar cheese", 20), ("Salad greens", 30),
           ("Tomato", 60), ("Hummus", 30)]),
        t("tuna-salad", "Tuna salad & toast", "🥗", .lunch,
          [("Tuna (canned)", 142), ("Salad greens", 80), ("Tomato", 80), ("Cucumber", 80), ("Olive oil", 7),
           ("Whole wheat bread", 64)]),
        t("chicken-salad", "Chicken salad", "🥗", .lunch,
          [("Chicken breast", 170), ("Salad greens", 120), ("Parmesan", 10), ("Vinaigrette", 30), ("Black beans", 80)]),
        // Dinner
        t("salmon-dinner", "Salmon, potatoes & green beans", "🐟", .dinner,
          [("Salmon", 170), ("Potato", 250), ("Green beans", 120), ("Olive oil", 5)]),
        t("turkey-chili", "Turkey chili", "🌶️", .dinner,
          [("Ground turkey", 170), ("Black beans", 130), ("Tomato", 150), ("Onion", 50), ("Cheddar cheese", 15)]),
        t("steak-dinner", "Steak & sweet potato", "🥩", .dinner,
          [("Steak", 170), ("Sweet potato", 200), ("Asparagus", 120), ("Butter", 5)]),
        t("chicken-pasta", "Chicken pasta", "🍝", .dinner,
          [("Chicken breast", 150), ("Pasta", 180), ("Spinach", 60), ("Parmesan", 10), ("Olive oil", 5)]),
        t("shrimp-stirfry", "Shrimp stir-fry", "🍤", .dinner,
          [("Shrimp", 200), ("White rice", 180), ("Bell pepper", 100), ("Broccoli", 80), ("Soy sauce", 15), ("Olive oil", 5)]),
        // Snack
        t("shake-banana", "Protein shake & banana", "🥤", .snack,
          [("Whey protein", 35), ("Milk", 240), ("Banana", 118)]),
        t("cottage-berries", "Cottage cheese & berries", "🍓", .snack,
          [("Cottage cheese", 225), ("Strawberries", 120)]),
        t("bar-apple", "Protein bar & apple", "🍎", .snack,
          [("Protein bar", 60), ("Apple", 180)]),
        t("yogurt-almonds", "Greek yogurt & almonds", "🥜", .snack,
          [("Greek yogurt", 200), ("Almonds", 20)])
    ]

    static func food(_ name: String) -> FoodFacts? {
        NutritionTable.foods.first { $0.name == name }
    }

    // MARK: - Pricing

    static func meal(_ template: Template, scale: Double = 1) -> Meal {
        let items = template.ingredients.map { Ingredient(food: $0.food, grams: $0.grams * scale) }
        var cal = 0.0, p = 0.0, c = 0.0, f = 0.0
        for i in items {
            guard let facts = food(i.food) else { continue }
            let k = i.grams / 100
            cal += facts.calories * k
            p += facts.protein * k
            c += facts.carbs * k
            f += facts.fat * k
        }
        return Meal(templateID: template.id, name: template.name, emoji: template.emoji, slot: template.slot,
                    ingredients: items, calories: cal.rounded(), protein: p.rounded(), carbs: c.rounded(), fat: f.rounded())
    }

    /// The template sized to `calories` (kept within half to double the
    /// base portion, in 5 % steps).
    static func meal(_ template: Template, calories: Double) -> Meal {
        let base = meal(template).calories
        guard base > 0 else { return meal(template) }
        let scale = min(2, max(0.5, ((calories / base) * 20).rounded() / 20))
        return meal(template, scale: scale)
    }

    // MARK: - Choosing

    /// A slot's templates, best first: closest to the share of calories
    /// your protein target needs (a little over is fine, double isn't),
    /// plus a nudge for foods you already eat, then rotated by `seed`.
    /// Without a target, the most protein per calorie wins.
    static func ranked(_ slot: Slot, preferred: Set<String>, seed: Int = 0, targetDensity: Double? = nil) -> [Template] {
        let options = library.filter { $0.slot == slot }
        let scored = options.map { t -> (Template, Double) in
            let m = meal(t)
            let density = m.calories > 0 ? m.protein * 4 / m.calories : 0
            let liked = Double(t.ingredients.filter { preferred.contains($0.food) }.count)
            let fit = targetDensity.map { -abs(density - $0 * 1.15) } ?? density
            return (t, fit + liked * 0.08)
        }
        let sorted = scored.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }.map(\.0)
        guard !sorted.isEmpty else { return [] }
        let shift = ((seed % sorted.count) + sorted.count) % sorted.count
        return Array(sorted[shift...] + sorted[..<shift])
    }

    /// How many go-to options rotate through each slot.
    static func rotation(_ slot: Slot) -> Int { slot == .lunch || slot == .dinner ? 3 : 2 }

    static func day(_ date: Date, index: Int, calories: Double, protein: Double,
                    preferred: Set<String>, seed: Int) -> DayPlan {
        let targetDensity = calories > 0 && protein > 0 ? protein * 4 / calories : nil
        var meals = Slot.allCases.compactMap { slot -> Meal? in
            let options = ranked(slot, preferred: preferred, seed: seed, targetDensity: targetDensity).prefix(rotation(slot))
            guard !options.isEmpty else { return nil }
            let pick = options[options.startIndex + index % options.count]
            return meal(pick, calories: calories * slot.share)
        }
        // Short on protein? Make the snack the shake.
        let total = meals.reduce(0) { $0 + $1.protein }
        if total < protein * 0.9, let i = meals.firstIndex(where: { $0.slot == .snack }),
           meals[i].templateID != "shake-banana",
           let shake = library.first(where: { $0.id == "shake-banana" }) {
            meals[i] = meal(shake, calories: calories * Slot.snack.share)
        }
        return DayPlan(date: date, meals: meals)
    }

    static func week(start: Date, calories: Double, protein: Double, preferred: Set<String> = [],
                     seed: Int = 0, calendar: Calendar = .current) -> WeekPlan {
        let first = calendar.startOfDay(for: start)
        let days = (0..<7).compactMap { i -> DayPlan? in
            guard let d = calendar.date(byAdding: .day, value: i, to: first) else { return nil }
            return day(d, index: i, calories: calories, protein: protein, preferred: preferred, seed: seed)
        }
        return WeekPlan(start: first, days: days, calories: calories, protein: protein, seed: seed)
    }

    /// Next option for one slot on one day, sized to the same calories.
    static func swap(_ plan: WeekPlan, day: Int, slot: Slot) -> WeekPlan {
        guard plan.days.indices.contains(day),
              let i = plan.days[day].meals.firstIndex(where: { $0.slot == slot }) else { return plan }
        let options = library.filter { $0.slot == slot }
        guard let at = options.firstIndex(where: { $0.id == plan.days[day].meals[i].templateID }) else { return plan }
        let next = options[(at + 1) % options.count]
        var out = plan
        out.days[day].meals[i] = meal(next, calories: plan.calories * slot.share)
        return out
    }

    /// Food names (NutritionTable) behind things you log, for preferences.
    static func preferredFoods(fromNames names: [String]) -> Set<String> {
        Set(names.compactMap { NutritionTable.match($0)?.name })
    }

    // MARK: - Groceries

    private static let protein: Set<String> = ["Chicken breast", "Chicken thigh", "Ground beef", "Steak", "Ground turkey",
                                                "Turkey deli meat", "Pork chop", "Bacon", "Salmon", "Tuna (canned)",
                                                "White fish", "Shrimp", "Egg", "Egg whites", "Tofu"]
    private static let dairy: Set<String> = ["Greek yogurt", "Cottage cheese", "Milk", "Cheddar cheese", "Mozzarella",
                                             "Parmesan", "Feta", "Butter", "Sour cream"]
    private static let produce: Set<String> = ["Broccoli", "Spinach", "Salad greens", "Tomato", "Cucumber", "Carrots",
                                               "Green beans", "Asparagus", "Cauliflower", "Bell pepper", "Onion",
                                               "Mushrooms", "Zucchini", "Brussels sprouts", "Corn", "Potato", "Sweet potato",
                                               "Banana", "Apple", "Orange", "Strawberries", "Blueberries", "Grapes",
                                               "Avocado", "Pineapple", "Watermelon", "Garlic"]
    static let aisles = ["Protein", "Produce", "Dairy", "Pantry"]

    static func aisle(_ food: String) -> String {
        if protein.contains(food) { return "Protein" }
        if dairy.contains(food) { return "Dairy" }
        if produce.contains(food) { return "Produce" }
        return "Pantry"
    }

    static func groceries(_ plan: WeekPlan) -> [GroceryItem] {
        var grams: [String: Double] = [:]
        for d in plan.days { for m in d.meals { for i in m.ingredients { grams[i.food, default: 0] += i.grams } } }
        return grams.map { GroceryItem(food: $0.key, aisle: aisle($0.key), amount: shoppingAmount($0.key, grams: $0.value)) }
            .sorted { (aisles.firstIndex(of: $0.aisle) ?? 9, $0.food) < (aisles.firstIndex(of: $1.aisle) ?? 9, $1.food) }
    }

    /// What to buy: "2½ lb", "18 eggs", "3 cups (dry)", "2 × 32 oz tubs".
    static func shoppingAmount(_ name: String, grams: Double) -> String {
        func up(_ v: Double, _ step: Double) -> Double { max(step, (v / step).rounded(.up) * step) }
        switch name {
        case "Egg":
            return "\(Int(up(grams / 50, 1))) eggs"
        case "Egg whites":
            return "\(fraction(up(grams / 243, 0.5))) cups liquid"
        case "White rice", "Brown rice":
            return "\(fraction(up(grams / 3 / 185, 0.5))) cups (dry)"
        case "Pasta":
            return "\(fraction(up(grams / 2.3 / 453.6, 0.25))) lb (dry)"
        case "Greek yogurt":
            let tubs = Int(up(grams / 907, 1))
            return "\(tubs) × 32 oz tub\(tubs == 1 ? "" : "s")"
        case "Milk":
            return grams > 1_900 ? "1 gallon" : "½ gallon"
        case "Whey protein":
            return "\(Int(up(grams / 30, 1))) scoops"
        case "Whole wheat bread", "Bread":
            return "\(Int(up(grams / 32 / 20, 1))) loaf"
        case "Flour tortilla", "Corn tortilla", "Protein bar":
            return "\(Int(up(grams / (food(name)?.measures["piece"] ?? 45), 1)))"
        case "Tuna (canned)":
            return "\(Int(up(grams / 142, 1))) cans"
        case "Black beans":
            return "\(Int(up(grams / 240, 1))) cans (15 oz)"
        case "Oatmeal", "Granola":
            return "\(fraction(up(grams / (food(name)?.measures["cup"] ?? 81), 0.5))) cups"
        default:
            break
        }
        if let piece = food(name)?.measures["piece"], produce.contains(name), piece >= 100 {
            return "\(Int(up(grams / piece, 1)))"
        }
        if protein.contains(name) || produce.contains(name) || dairy.contains(name) && grams > 200 {
            return "\(fraction(up(grams / 453.6, 0.25))) lb"
        }
        return "\(Int(up(grams / 28.35, 1))) oz"
    }

    // MARK: - Formatting

    /// Kitchen amount for one ingredient: "6 oz chicken breast", "1¼ cups white rice", "2 eggs".
    static func amountText(_ i: Ingredient) -> String {
        let lower = i.food.lowercased()
        guard let facts = food(i.food) else { return "\(Int(i.grams)) g \(lower)" }
        func q(_ v: Double, _ step: Double = 0.25) -> String { fraction(max(step, (v / step).rounded() * step)) }
        if protein.contains(i.food), i.food != "Egg", i.food != "Egg whites", i.food != "Tuna (canned)" {
            return "\(q(i.grams / 28.35, 0.5)) oz \(lower)"
        }
        // Tubs of yogurt read better in cups; berries and florets aren't counted one by one.
        let units = dairy.contains(i.food) ? ["cup", "slice"] : ["piece", "slice", "scoop", "can", "cup"]
        for unit in units {
            guard let g = facts.measures[unit], g > 0 else { continue }
            if unit == "piece", g < 40, i.food != "Egg", i.food != "Almonds" { continue }
            let n = i.grams / g
            guard n >= 0.2 else { continue }
            // Eggs and nuts are counted whole.
            let amount = unit == "piece" && (i.food == "Egg" || i.food == "Almonds") ? String(max(1, Int(n.rounded()))) : q(n)
            let plural = n > 1.1
            switch unit {
            case "piece":
                return i.food == "Egg" ? "\(amount) egg\(plural ? "s" : "")" : "\(amount) \(lower)"
            case "cup":
                return "\(amount) cup\(plural ? "s" : "") \(lower)"
            default:
                return "\(amount) \(unit)\(plural ? "s" : "") \(lower)"
            }
        }
        return "\(Int(i.grams.rounded())) g \(lower)"
    }

    static func fraction(_ v: Double) -> String {
        let whole = Int(v)
        let rest = v - Double(whole)
        let part: String
        switch rest {
        case 0.2..<0.3:  part = "¼"
        case 0.45..<0.55: part = "½"
        case 0.7..<0.8:  part = "¾"
        default:         part = ""
        }
        if part.isEmpty { return String(Int(v.rounded())) }
        return whole == 0 ? part : "\(whole)\(part)"
    }
}
