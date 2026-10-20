//
//  MealPlanner.swift
//  Dialed
//
//  "I'm at Chipotle — what should I get?" Works out how much of today's
//  calories and protein this meal should use, then builds up to three
//  orders from the menu that fit: the most protein for the calories, the
//  lightest, and the most filling. Pure Foundation, tested.
//

import Foundation

enum MealPlanner {

    /// What's left today, and how much of it this meal should use.
    struct Budget: Equatable {
        var caloriesLeft: Double
        var proteinLeft: Double
        /// Share of what's left this meal gets (later meals need the rest).
        var share: Double

        var calories: Double { max(350, caloriesLeft * share) }
        var protein: Double { max(25, proteinLeft * share) }

        /// Breakfast-time keeps room for two meals, lunch for one,
        /// dinner can use (almost) everything.
        static func forNow(caloriesLeft: Double, proteinLeft: Double, hour: Int, lastMeal: Bool = false) -> Budget {
            let share: Double
            if lastMeal { share = 0.95 }
            else if hour < 11 { share = 0.35 }
            else if hour < 16 { share = 0.5 }
            else { share = 0.9 }
            return Budget(caloriesLeft: max(0, caloriesLeft), proteinLeft: max(0, proteinLeft), share: share)
        }
    }

    struct Pick: Equatable, Identifiable {
        enum Kind: String { case protein, light, filling }
        let kind: Kind
        let items: [MenuItem]

        var id: String { kind.rawValue + items.map(\.name).joined() }
        var calories: Double { items.reduce(0) { $0 + $1.calories } }
        var protein: Double { items.reduce(0) { $0 + $1.protein } }
        var carbs: Double { items.reduce(0) { $0 + $1.carbs } }
        var fat: Double { items.reduce(0) { $0 + $1.fat } }
        var tips: [String] { items.compactMap(\.tip) }

        var title: String {
            switch kind {
            case .protein: return "Best for your goals"
            case .light:   return "Lightest"
            case .filling: return "Most filling"
            }
        }

        var name: String { items.filter { $0.role != .drink || $0.calories > 0 }.map(\.name).joined(separator: " + ") }
    }

    /// Every order worth considering: a main, optionally a side, and a
    /// zero-calorie drink when the menu has one.
    static func combos(_ menu: [MenuItem]) -> [[MenuItem]] {
        let mains = menu.filter { $0.role == .main }
        let sides = menu.filter { $0.role == .side }
        let freeDrink = menu.first { $0.role == .drink && $0.calories <= 10 }
        var out: [[MenuItem]] = []
        for main in mains {
            out.append([main])
            for side in sides { out.append([main, side]) }
            // Two small mains (nuggets + a sandwich) — never two bowls.
            if isStackable(main) {
                for other in mains where other.name > main.name && isStackable(other) {
                    out.append([main, other])
                }
            }
        }
        guard let freeDrink else { return out }
        return out.map { $0 + [freeDrink] }
    }

    /// Up to three picks that fit the budget, best first. If nothing fits,
    /// the lightest order on the menu.
    static func picks(menu: [MenuItem], budget: Budget) -> [Pick] {
        let all = combos(menu)
        let cap = budget.calories * 1.08
        let fitting = all.filter { total($0, \.calories) <= cap }
        guard !fitting.isEmpty else {
            return all.min { total($0, \.calories) < total($1, \.calories) }.map { [Pick(kind: .light, items: $0)] } ?? []
        }

        func score(_ c: [MenuItem]) -> Double {
            let cal = total(c, \.calories), p = total(c, \.protein)
            let proteinFit = min(1, p / budget.protein)              // reach the protein
            let use = min(1, cal / budget.calories)                  // use the calories, don't waste them
            let density = p / max(cal, 1) * 100                      // g per 100 kcal
            return proteinFit * 3 + use * 0.5 + density * 0.1 - Double(c.count - 1) * 0.15
        }

        var picks: [Pick] = []
        if let best = fitting.max(by: { score($0) < score($1) }) {
            picks.append(Pick(kind: .protein, items: best))
        }
        // Lightest that still brings real protein.
        let light = fitting
            .filter { total($0, \.protein) >= min(20, budget.protein * 0.5) }
            .min { total($0, \.calories) < total($1, \.calories) }
        if let light, !picks.contains(where: { same($0.items, light) }) {
            picks.append(Pick(kind: .light, items: light))
        }
        // Most food for the budget (calories closest to it, then protein).
        let filling = fitting.max {
            (total($0, \.calories), total($0, \.protein)) < (total($1, \.calories), total($1, \.protein))
        }
        if let filling, !picks.contains(where: { same($0.items, filling) || sameMain($0.items, filling) }) {
            picks.append(Pick(kind: .filling, items: filling))
        }
        return picks
    }

    private static func total(_ items: [MenuItem], _ key: KeyPath<MenuItem, Double>) -> Double {
        items.reduce(0) { $0 + $1[keyPath: key] }
    }

    private static func isStackable(_ item: MenuItem) -> Bool {
        let n = item.name.lowercased()
        return item.calories <= 420 && !["bowl", "plate", "salad", "box", "burrito", "wrap"].contains(where: n.contains)
    }

    private static func sameMain(_ a: [MenuItem], _ b: [MenuItem]) -> Bool {
        Set(a.filter { $0.role == .main }.map(\.name)) == Set(b.filter { $0.role == .main }.map(\.name))
    }

    private static func same(_ a: [MenuItem], _ b: [MenuItem]) -> Bool {
        Set(a.map(\.name)) == Set(b.map(\.name))
    }
}
