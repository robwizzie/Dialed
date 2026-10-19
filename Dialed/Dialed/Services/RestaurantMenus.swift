//
//  RestaurantMenus.swift
//  Dialed
//
//  A small built-in guide to popular chains: the orders that matter on a
//  cut, with approximate calories and macros from each chain's published
//  nutrition (rounded; recipes change, so treat them as estimates). The
//  meal planner builds picks from these; anywhere else, Apple
//  Intelligence suggests an order instead.
//

import Foundation

struct MenuItem: Equatable, Hashable {
    enum Role: String { case main, side, drink }

    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    var role: Role = .main
    /// How to order it lighter or with more protein.
    var tip: String? = nil
}

struct Restaurant: Equatable, Identifiable {
    let name: String
    let emoji: String
    let aliases: [String]
    let items: [MenuItem]
    var id: String { name }
}

enum RestaurantMenus {
    private static func m(_ name: String, _ cal: Double, _ p: Double, _ c: Double, _ f: Double, tip: String? = nil) -> MenuItem {
        MenuItem(name: name, calories: cal, protein: p, carbs: c, fat: f, role: .main, tip: tip)
    }
    private static func s(_ name: String, _ cal: Double, _ p: Double, _ c: Double, _ f: Double, tip: String? = nil) -> MenuItem {
        MenuItem(name: name, calories: cal, protein: p, carbs: c, fat: f, role: .side, tip: tip)
    }
    private static func d(_ name: String, _ cal: Double, _ p: Double, _ c: Double, _ f: Double) -> MenuItem {
        MenuItem(name: name, calories: cal, protein: p, carbs: c, fat: f, role: .drink)
    }

    static let all: [Restaurant] = [
        Restaurant(name: "Chipotle", emoji: "🌯", aliases: ["chipotle mexican grill"], items: [
            m("Chicken burrito bowl (lettuce, fajita veg, pico, black beans)", 455, 47, 37, 13, tip: "Skip the rice and cheese; ask for extra fajita veg"),
            m("Double chicken bowl (brown rice, beans, salsa)", 730, 80, 66, 18, tip: "Half rice saves ~105 kcal"),
            m("Steak salad (lettuce, fajita veg, salsa, vinaigrette on the side)", 420, 32, 26, 22, tip: "Use half the vinaigrette"),
            m("Chicken burrito (rice, beans, salsa, cheese)", 1_040, 60, 116, 37, tip: "Make it a bowl to save ~320 kcal"),
            m("Sofritas bowl (rice, beans, veg, salsa)", 640, 24, 92, 20),
            m("Lifestyle Bowl — High Protein", 885, 81, 64, 33),
            s("Side of chicken", 180, 32, 0, 7),
            s("Chips & salsa", 565, 7, 76, 27),
            d("Diet soda / water", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Chick-fil-A", emoji: "🐔", aliases: ["chickfila", "chick fil a", "cfa"], items: [
            m("Grilled Chicken Sandwich", 390, 28, 44, 12),
            m("12-ct Grilled Nuggets", 200, 38, 2, 5, tip: "Zesty Buffalo sauce is only 25 kcal"),
            m("Grilled Chicken Cool Wrap", 660, 42, 29, 43, tip: "Skip the avocado lime dressing to save ~300 kcal"),
            m("8-ct Nuggets", 250, 27, 11, 11),
            m("Chick-fil-A Chicken Sandwich", 420, 29, 41, 18),
            m("Spicy Southwest Salad with grilled filet", 680, 36, 30, 46, tip: "Use a light dressing"),
            s("Kale Crunch Side", 170, 4, 12, 13),
            s("Fruit cup (medium)", 70, 1, 18, 0),
            s("Waffle fries (medium)", 420, 5, 45, 24),
            d("Diet lemonade", 50, 0, 13, 0)
        ]),
        Restaurant(name: "McDonald's", emoji: "🍔", aliases: ["mcdonalds", "mcd", "mickey d's"], items: [
            m("McDouble", 400, 22, 33, 20, tip: "No cheese saves ~50 kcal"),
            m("Quarter Pounder with Cheese", 520, 30, 42, 26),
            m("10-pc Chicken McNuggets", 410, 23, 25, 24),
            m("Egg McMuffin", 310, 17, 30, 13),
            m("Hamburger", 250, 12, 31, 9),
            m("McChicken", 400, 14, 39, 21),
            s("Apple slices", 15, 0, 4, 0),
            s("Small fries", 230, 3, 29, 11),
            d("Diet Coke", 0, 0, 0, 0),
            d("Large black coffee", 5, 0, 0, 0)
        ]),
        Restaurant(name: "Subway", emoji: "🥪", aliases: ["subway sandwiches"], items: [
            m("6\" Rotisserie-style chicken on wheat, veggies", 340, 29, 41, 7, tip: "Mustard or vinegar instead of mayo"),
            m("Footlong turkey on wheat, veggies", 560, 36, 92, 6),
            m("6\" Turkey on wheat, veggies", 280, 18, 46, 3),
            m("Protein Bowl — double chicken", 410, 66, 10, 13),
            m("6\" Steak & cheese on wheat", 380, 26, 43, 11),
            m("Footlong Italian B.M.T.", 820, 38, 92, 32),
            s("Apple slices", 35, 0, 9, 0),
            s("Baked chips", 130, 2, 24, 3),
            d("Water", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Taco Bell", emoji: "🌮", aliases: ["tacobell"], items: [
            m("Power Menu Bowl — chicken", 460, 26, 47, 19, tip: "Order it \"fresco\" or no sour cream"),
            m("2 Chicken Soft Tacos", 320, 24, 30, 12),
            m("Cantina Chicken Bowl", 490, 27, 46, 22),
            m("Bean Burrito", 350, 13, 54, 9),
            m("Crunchwrap Supreme", 530, 16, 71, 21),
            m("3 Crunchy Tacos fresco", 450, 24, 39, 24),
            s("Black beans", 50, 2, 8, 1),
            d("Diet Baja Blast", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Starbucks", emoji: "☕️", aliases: ["sbux", "starbucks coffee"], items: [
            m("Egg White & Roasted Red Pepper Egg Bites", 170, 12, 11, 8),
            m("Turkey Bacon, Cheddar & Egg White Sandwich", 230, 17, 28, 5),
            m("Spinach, Feta & Egg White Wrap", 290, 20, 34, 8),
            m("Protein Box — eggs & cheese", 460, 23, 39, 23),
            m("Rolled & Steel-Cut Oatmeal", 160, 5, 28, 2.5),
            m("Chicken & Quinoa Protein Bowl", 420, 27, 42, 17),
            s("Bacon & Gruyère Egg Bites", 300, 19, 9, 20),
            d("Grande Cold Brew", 5, 0, 0, 0),
            d("Grande Protein Cold Foam Cold Brew", 250, 17, 22, 10),
            d("Grande Latte (2%)", 190, 13, 19, 7)
        ]),
        Restaurant(name: "Wendy's", emoji: "🟥", aliases: ["wendys"], items: [
            m("Grilled Chicken Sandwich", 370, 34, 37, 10),
            m("Jr. Cheeseburger", 290, 15, 26, 14),
            m("Dave's Single", 590, 29, 39, 34),
            m("Apple Pecan Salad (full, grilled chicken)", 560, 37, 37, 30, tip: "Half the pecans and dressing saves ~150 kcal"),
            m("10-pc Nuggets", 450, 23, 28, 28),
            s("Small chili", 240, 17, 23, 7),
            s("Plain baked potato", 270, 7, 61, 0),
            d("Diet Coke", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Panera", emoji: "🥗", aliases: ["panera bread"], items: [
            m("Green Goddess Cobb Salad with chicken", 530, 42, 25, 31),
            m("Mediterranean Bowl with chicken", 640, 40, 60, 26),
            m("Teriyaki Chicken & Broccoli Bowl", 650, 35, 92, 15),
            m("Half Turkey sandwich + cup of soup", 510, 26, 59, 18),
            m("Chicken Noodle Soup (bowl)", 160, 13, 18, 4),
            s("Apple", 80, 0, 21, 0),
            d("Unsweetened iced tea", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Sweetgreen", emoji: "🥬", aliases: ["sweet green"], items: [
            m("Kale Caesar with chicken", 430, 34, 20, 26),
            m("Harvest Bowl", 705, 36, 59, 37, tip: "Light dressing saves ~100 kcal"),
            m("Chicken Pesto Parm", 530, 41, 41, 24),
            m("Guacamole Greens", 525, 29, 35, 32),
            s("Extra chicken", 130, 23, 1, 4),
            d("Water", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Cava", emoji: "🫒", aliases: [], items: [
            m("Greens + grains bowl, chicken, hummus, veggies", 560, 41, 40, 27, tip: "Swap one dip for extra veg"),
            m("Salad bowl, double chicken, tzatziki, veggies", 470, 58, 18, 19),
            m("Chicken + rice bowl", 720, 44, 66, 30),
            m("Lamb meatball pita", 780, 34, 76, 38),
            s("Pita chips", 250, 4, 28, 13),
            d("Water", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Panda Express", emoji: "🐼", aliases: ["panda"], items: [
            m("Plate: Grilled Teriyaki Chicken + Super Greens ×2", 410, 40, 25, 15),
            m("Bowl: String Bean Chicken + Super Greens", 280, 18, 20, 14),
            m("Bowl: Grilled Teriyaki Chicken + white rice", 680, 42, 95, 14),
            m("Bowl: Orange Chicken + Chow Mein", 1_000, 33, 129, 39),
            s("Super Greens", 90, 6, 10, 3),
            d("Water", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Five Guys", emoji: "🍟", aliases: ["5 guys", "five guys burgers"], items: [
            m("Little Hamburger, lettuce wrap", 390, 23, 3, 31),
            m("Little Cheeseburger", 615, 27, 40, 36),
            m("Hamburger (2 patties), lettuce wrap", 700, 39, 4, 58),
            m("Grilled cheese", 470, 11, 41, 26),
            s("Little fries", 530, 8, 72, 23),
            d("Diet Coke", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Jersey Mike's", emoji: "🥖", aliases: ["jersey mikes"], items: [
            m("#7 Turkey & Provolone, regular, Mike's Way", 690, 39, 72, 26),
            m("#7 Turkey, \"in a tub\" (no bread)", 330, 34, 9, 18),
            m("#17 Mike's Famous Philly, regular", 830, 52, 74, 34),
            m("Chicken Philly in a tub", 420, 46, 10, 20),
            s("Baked chips", 130, 2, 24, 3),
            d("Water", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Wingstop", emoji: "🍗", aliases: ["wing stop"], items: [
            m("8 Classic wings, dry rub (Lemon Pepper)", 720, 64, 0, 52),
            m("8 Classic wings, Original Hot", 650, 64, 2, 42),
            m("3 Plain tenders", 360, 33, 18, 18),
            s("Veggie sticks", 15, 0, 3, 0),
            s("Regular fries", 400, 5, 52, 19),
            d("Water", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Burger King", emoji: "👑", aliases: ["bk"], items: [
            m("Whopper Jr. (no mayo)", 250, 13, 28, 10),
            m("Whopper", 670, 31, 51, 40, tip: "No mayo saves ~150 kcal"),
            m("8-pc Chicken Nuggets", 360, 16, 21, 23),
            m("Hamburger", 250, 13, 29, 10),
            s("Small fries", 320, 4, 44, 14),
            d("Diet Coke", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Dunkin'", emoji: "🍩", aliases: ["dunkin", "dunkin donuts", "dd"], items: [
            m("Egg White & Veggie Omelet Bites", 170, 13, 11, 8),
            m("Turkey Sausage, Egg & Cheese on English muffin", 440, 26, 33, 22),
            m("Wake-Up Wrap — egg & cheese", 180, 7, 14, 10),
            m("Avocado Toast", 240, 6, 34, 9),
            s("Hash browns (6)", 130, 1, 15, 7),
            d("Medium cold brew, black", 5, 0, 1, 0),
            d("Medium latte, skim", 140, 13, 20, 0)
        ]),
        Restaurant(name: "Qdoba", emoji: "🫔", aliases: [], items: [
            m("Chicken bowl, no rice, black beans, fajita veg, pico", 470, 41, 30, 19),
            m("Protein Bowl", 720, 58, 51, 30),
            m("Chicken burrito (rice, beans, pico)", 960, 51, 120, 29),
            s("Side of chicken", 150, 23, 1, 6),
            d("Water", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Popeyes", emoji: "🍤", aliases: [], items: [
            m("3-pc Blackened Tenders", 170, 26, 2, 2),
            m("5-pc Blackened Tenders", 280, 44, 3, 4),
            m("Classic Chicken Sandwich", 700, 28, 50, 42),
            s("Green beans (regular)", 55, 2, 7, 2),
            s("Red beans & rice (regular)", 250, 8, 32, 11),
            d("Diet soda", 0, 0, 0, 0)
        ]),
        Restaurant(name: "Domino's", emoji: "🍕", aliases: ["dominos"], items: [
            m("2 slices medium thin-crust chicken & veggie", 380, 22, 34, 18),
            m("2 slices medium hand-tossed cheese", 420, 17, 54, 15),
            m("Chicken Caesar salad (no croutons)", 230, 21, 7, 13),
            s("8-pc plain boneless chicken", 400, 30, 22, 20),
            d("Diet Coke", 0, 0, 0, 0)
        ])
    ]

    /// Best match for what you typed ("chickfila", "mcd", "panera bread").
    static func find(_ text: String) -> Restaurant? {
        let q = normalize(text)
        guard !q.isEmpty else { return nil }
        if let exact = all.first(where: { normalize($0.name) == q || $0.aliases.map(normalize).contains(q) }) {
            return exact
        }
        return all.first { normalize($0.name).hasPrefix(q) || q.hasPrefix(normalize($0.name)) }
            ?? all.first { r in ([r.name] + r.aliases).map(normalize).contains { $0.contains(q) || q.contains($0) } }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
