//
//  NutritionTable.swift
//  Dialed
//
//  Everyday foods with their nutrition per 100 g (USDA-style values,
//  rounded) and what common household measures weigh — a cup of
//  broccoli, a teaspoon of olive oil, a piece of sushi roll. Meal
//  estimates do their math here instead of trusting a language model's
//  arithmetic. Pure Foundation.
//

import Foundation

struct FoodFacts: Equatable {
    let name: String
    let aliases: [String]
    /// Per 100 g.
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    /// Grams in one of each measure ("cup", "tbsp", "piece", "slice", "oz"…).
    let measures: [String: Double]
    /// What "some broccoli" means when no amount is given.
    let defaultMeasure: (unit: String, amount: Double)

    static func == (a: FoodFacts, b: FoodFacts) -> Bool { a.name == b.name }

    func grams(_ amount: Double, _ unit: String) -> Double? {
        switch unit {
        case "g": return amount
        case "kg": return amount * 1_000
        case "oz": return measures["oz"].map { $0 * amount } ?? amount * 28.35
        case "lb": return amount * 453.6
        case "ml": return amount
        default: return measures[unit].map { $0 * amount }
        }
    }
}

enum NutritionTable {
    private static func f(_ name: String, _ aliases: [String], _ cal: Double, _ p: Double, _ c: Double, _ fat: Double,
                          _ measures: [String: Double], default d: (String, Double)) -> FoodFacts {
        FoodFacts(name: name, aliases: aliases, calories: cal, protein: p, carbs: c, fat: fat,
                  measures: measures, defaultMeasure: (d.0, d.1))
    }

    static let foods: [FoodFacts] = [
        // Vegetables
        f("Broccoli", ["broccoli", "broccolini"], 34, 2.8, 6.6, 0.4, ["cup": 91, "piece": 11, "head": 300], default: ("cup", 1)),
        f("Spinach", ["spinach"], 23, 2.9, 3.6, 0.4, ["cup": 30], default: ("cup", 2)),
        f("Salad greens", ["salad", "greens", "lettuce", "romaine", "mixed greens", "arugula", "kale"], 17, 1.4, 3, 0.2, ["cup": 47], default: ("cup", 2)),
        f("Tomato", ["tomato", "tomatoes", "cherry tomatoes"], 18, 0.9, 3.9, 0.2, ["piece": 123, "cup": 149], default: ("piece", 1)),
        f("Cucumber", ["cucumber"], 15, 0.7, 3.6, 0.1, ["piece": 300, "cup": 104], default: ("cup", 1)),
        f("Carrots", ["carrot", "carrots"], 41, 0.9, 10, 0.2, ["piece": 61, "cup": 128], default: ("cup", 1)),
        f("Green beans", ["green beans", "string beans"], 31, 1.8, 7, 0.2, ["cup": 125], default: ("cup", 1)),
        f("Asparagus", ["asparagus"], 20, 2.2, 3.9, 0.1, ["piece": 16, "cup": 134], default: ("cup", 1)),
        f("Cauliflower", ["cauliflower"], 25, 1.9, 5, 0.3, ["cup": 107], default: ("cup", 1)),
        f("Bell pepper", ["bell pepper", "peppers", "pepper strips"], 31, 1, 6, 0.3, ["piece": 119, "cup": 92], default: ("piece", 1)),
        f("Onion", ["onion", "onions"], 40, 1.1, 9.3, 0.1, ["piece": 110, "cup": 160], default: ("piece", 0.5)),
        f("Mushrooms", ["mushroom", "mushrooms"], 22, 3.1, 3.3, 0.3, ["cup": 70, "piece": 18], default: ("cup", 1)),
        f("Zucchini", ["zucchini", "squash"], 17, 1.2, 3.1, 0.3, ["piece": 196, "cup": 124], default: ("cup", 1)),
        f("Brussels sprouts", ["brussels sprouts", "brussel sprouts"], 43, 3.4, 9, 0.3, ["cup": 88, "piece": 19], default: ("cup", 1)),
        f("Corn", ["corn"], 86, 3.3, 19, 1.4, ["cup": 145, "piece": 90], default: ("cup", 1)),
        f("Potato", ["potato", "potatoes", "baked potato", "mashed potatoes"], 93, 2.5, 21, 0.1, ["piece": 173, "cup": 156], default: ("piece", 1)),
        f("Sweet potato", ["sweet potato", "yam"], 90, 2, 21, 0.2, ["piece": 114, "cup": 200], default: ("piece", 1)),
        f("French fries", ["fries", "french fries"], 312, 3.4, 41, 15, ["serving": 117, "piece": 5, "cup": 60], default: ("serving", 1)),

        // Fruit
        f("Banana", ["banana", "bananas"], 89, 1.1, 23, 0.3, ["piece": 118], default: ("piece", 1)),
        f("Apple", ["apple", "apples"], 52, 0.3, 14, 0.2, ["piece": 182], default: ("piece", 1)),
        f("Orange", ["orange", "oranges", "clementine"], 47, 0.9, 12, 0.1, ["piece": 131], default: ("piece", 1)),
        f("Strawberries", ["strawberries", "strawberry"], 32, 0.7, 7.7, 0.3, ["cup": 152, "piece": 12], default: ("cup", 1)),
        f("Blueberries", ["blueberries", "berries", "raspberries", "blackberries"], 57, 0.7, 14, 0.3, ["cup": 148], default: ("cup", 1)),
        f("Grapes", ["grapes"], 69, 0.7, 18, 0.2, ["cup": 151, "piece": 5], default: ("cup", 1)),
        f("Avocado", ["avocado", "avocados"], 160, 2, 8.5, 14.7, ["piece": 136, "cup": 150, "slice": 15], default: ("piece", 0.5)),
        f("Pineapple", ["pineapple"], 50, 0.5, 13, 0.1, ["cup": 165], default: ("cup", 1)),
        f("Watermelon", ["watermelon", "melon", "cantaloupe"], 30, 0.6, 7.6, 0.2, ["cup": 152], default: ("cup", 1)),

        // Protein
        f("Chicken breast", ["chicken", "chicken breast", "grilled chicken", "rotisserie chicken"], 165, 31, 0, 3.6, ["piece": 172, "cup": 140, "serving": 113], default: ("oz", 5)),
        f("Chicken thigh", ["chicken thigh", "chicken thighs", "dark meat"], 209, 26, 0, 10.9, ["piece": 116], default: ("piece", 1)),
        f("Ground beef", ["ground beef", "beef", "burger patty", "hamburger patty"], 250, 26, 0, 15, ["piece": 113, "cup": 140], default: ("oz", 4)),
        f("Steak", ["steak", "sirloin", "ribeye", "flank steak", "filet"], 206, 30, 0, 9, ["piece": 225], default: ("oz", 6)),
        f("Ground turkey", ["ground turkey", "turkey burger"], 203, 27, 0, 10, ["piece": 113], default: ("oz", 4)),
        f("Turkey deli meat", ["turkey", "deli turkey", "sliced turkey"], 104, 17, 4, 2, ["slice": 28], default: ("slice", 3)),
        f("Pork chop", ["pork chop", "pork", "pork tenderloin"], 231, 26, 0, 13, ["piece": 145], default: ("piece", 1)),
        f("Bacon", ["bacon"], 541, 37, 1.4, 42, ["slice": 8, "piece": 8], default: ("slice", 2)),
        f("Salmon", ["salmon"], 206, 22, 0, 12, ["piece": 154, "serving": 113], default: ("oz", 5)),
        f("Tuna (canned)", ["tuna", "canned tuna"], 116, 26, 0, 0.8, ["can": 142, "cup": 154], default: ("can", 1)),
        f("White fish", ["cod", "tilapia", "white fish", "fish", "halibut"], 105, 23, 0, 0.9, ["piece": 150], default: ("oz", 5)),
        f("Shrimp", ["shrimp", "prawns"], 99, 24, 0.2, 0.3, ["piece": 6, "cup": 145], default: ("oz", 4)),
        f("Egg", ["egg", "eggs", "fried egg", "scrambled eggs", "hard boiled egg"], 143, 12.6, 0.7, 9.5, ["piece": 50], default: ("piece", 2)),
        f("Egg whites", ["egg white", "egg whites"], 52, 11, 0.7, 0.2, ["piece": 33, "cup": 243], default: ("cup", 0.5)),
        f("Tofu", ["tofu"], 144, 17, 3, 8.7, ["cup": 252, "piece": 85], default: ("cup", 0.5)),
        f("Whey protein", ["protein shake", "whey", "protein powder", "scoop of protein"], 400, 80, 8, 6, ["scoop": 30, "serving": 30, "piece": 30], default: ("scoop", 1)),

        // Grains and starches
        f("White rice", ["rice", "white rice", "jasmine rice", "sushi rice"], 130, 2.7, 28, 0.3, ["cup": 158, "serving": 158], default: ("cup", 1)),
        f("Brown rice", ["brown rice"], 123, 2.7, 26, 1, ["cup": 195], default: ("cup", 1)),
        f("Quinoa", ["quinoa"], 120, 4.4, 21, 1.9, ["cup": 185], default: ("cup", 1)),
        f("Pasta", ["pasta", "spaghetti", "penne", "noodles", "macaroni"], 158, 5.8, 31, 0.9, ["cup": 140, "serving": 140], default: ("cup", 1.5)),
        f("Bread", ["bread", "toast", "white bread", "sourdough"], 266, 8.9, 49, 3.3, ["slice": 32, "piece": 32], default: ("slice", 2)),
        f("Whole wheat bread", ["whole wheat bread", "wheat bread", "whole grain bread"], 252, 12, 43, 3.5, ["slice": 32], default: ("slice", 2)),
        f("Bagel", ["bagel"], 257, 10, 50, 1.6, ["piece": 105], default: ("piece", 1)),
        f("Burger bun", ["bun", "hamburger bun", "brioche bun"], 279, 9.4, 50, 4.3, ["piece": 52], default: ("piece", 1)),
        f("Flour tortilla", ["tortilla", "flour tortilla", "wrap"], 304, 8, 50, 7.6, ["piece": 45], default: ("piece", 1)),
        f("Corn tortilla", ["corn tortilla", "corn tortillas"], 218, 5.7, 45, 2.9, ["piece": 26], default: ("piece", 2)),
        f("Oatmeal", ["oats", "oatmeal", "rolled oats"], 389, 16.9, 66, 6.9, ["cup": 81, "serving": 40], default: ("cup", 0.5)),
        f("Cereal", ["cereal"], 380, 7, 84, 2, ["cup": 30, "serving": 30], default: ("cup", 1)),
        f("Granola", ["granola"], 471, 10, 64, 20, ["cup": 122], default: ("cup", 0.5)),
        f("Pancake", ["pancake", "pancakes"], 227, 6, 28, 10, ["piece": 77], default: ("piece", 3)),
        f("Waffle", ["waffle", "waffles"], 291, 7.9, 33, 14, ["piece": 75], default: ("piece", 2)),
        f("Black beans", ["black beans", "beans", "pinto beans", "kidney beans", "chickpeas"], 132, 8.9, 24, 0.5, ["cup": 172], default: ("cup", 0.5)),

        // Dairy
        f("Cheddar cheese", ["cheese", "cheddar", "american cheese", "swiss"], 403, 25, 1.3, 33, ["slice": 21, "cup": 113], default: ("slice", 1)),
        f("Mozzarella", ["mozzarella"], 280, 28, 3, 17, ["slice": 28, "cup": 113], default: ("oz", 1)),
        f("Parmesan", ["parmesan", "parm"], 431, 38, 4, 29, ["tbsp": 5, "cup": 100], default: ("tbsp", 2)),
        f("Feta", ["feta"], 264, 14, 4, 21, ["cup": 150, "tbsp": 9], default: ("oz", 1)),
        f("Cottage cheese", ["cottage cheese"], 98, 11, 3.4, 4.3, ["cup": 226], default: ("cup", 0.5)),
        f("Greek yogurt", ["greek yogurt", "yogurt", "skyr"], 59, 10, 3.6, 0.4, ["cup": 245, "piece": 170, "serving": 170], default: ("piece", 1)),
        f("Milk", ["milk", "2% milk"], 50, 3.3, 4.8, 2, ["cup": 244, "ml": 1], default: ("cup", 1)),
        f("Ice cream", ["ice cream"], 207, 3.5, 24, 11, ["cup": 132, "scoop": 66], default: ("cup", 0.5)),

        // Fats, sauces, sweeteners
        f("Olive oil", ["olive oil", "oil", "avocado oil", "vegetable oil", "canola oil", "evoo"], 884, 0, 0, 100, ["tbsp": 13.5, "tsp": 4.5, "drizzle": 4.5], default: ("tsp", 1)),
        f("Butter", ["butter"], 717, 0.9, 0.1, 81, ["tbsp": 14, "tsp": 4.7, "pat": 5], default: ("tsp", 1)),
        f("Honey", ["honey"], 304, 0.3, 82, 0, ["tbsp": 21, "tsp": 7, "drizzle": 7], default: ("tsp", 1)),
        f("Hot honey", ["hot honey", "mikes hot honey", "mike's hot honey"], 286, 0, 76, 0, ["tbsp": 21, "tsp": 7, "drizzle": 7], default: ("tsp", 1)),
        f("Maple syrup", ["maple syrup", "syrup"], 260, 0, 67, 0.1, ["tbsp": 20, "tsp": 6.7], default: ("tbsp", 2)),
        f("Sugar", ["sugar"], 387, 0, 100, 0, ["tbsp": 12.5, "tsp": 4.2], default: ("tsp", 1)),
        f("Peanut butter", ["peanut butter", "almond butter", "pb"], 588, 25, 20, 50, ["tbsp": 16, "tsp": 5.3], default: ("tbsp", 2)),
        f("Mayonnaise", ["mayo", "mayonnaise", "aioli"], 680, 1, 0.6, 75, ["tbsp": 14, "tsp": 4.7], default: ("tbsp", 1)),
        f("Ranch", ["ranch", "dressing", "caesar dressing", "blue cheese dressing"], 433, 1, 6, 45, ["tbsp": 15], default: ("tbsp", 2)),
        f("Vinaigrette", ["vinaigrette", "balsamic vinaigrette", "italian dressing"], 270, 0.2, 10, 25, ["tbsp": 15], default: ("tbsp", 2)),
        f("Ketchup", ["ketchup"], 101, 1, 27, 0.1, ["tbsp": 17, "tsp": 6], default: ("tbsp", 1)),
        f("BBQ sauce", ["bbq sauce", "barbecue sauce"], 172, 0.8, 41, 0.6, ["tbsp": 17], default: ("tbsp", 2)),
        f("Soy sauce", ["soy sauce", "tamari"], 53, 8, 5, 0.6, ["tbsp": 16, "tsp": 5.3], default: ("tbsp", 1)),
        f("Hot sauce", ["hot sauce", "sriracha", "buffalo sauce", "salsa"], 36, 1.5, 7, 0.2, ["tbsp": 16, "tsp": 5], default: ("tbsp", 1)),
        f("Guacamole", ["guacamole", "guac"], 155, 2, 8.6, 14, ["tbsp": 15, "cup": 230, "serving": 60], default: ("tbsp", 4)),
        f("Hummus", ["hummus"], 166, 7.9, 14, 9.6, ["tbsp": 15], default: ("tbsp", 2)),
        f("Sour cream", ["sour cream"], 198, 2.4, 4.6, 19, ["tbsp": 12], default: ("tbsp", 2)),
        f("Seasoning", ["salt", "pepper", "black pepper", "garlic powder", "spices", "seasoning", "herbs", "lemon juice", "mustard", "vinegar"],
          0, 0, 0, 0, ["tsp": 3, "tbsp": 9, "pinch": 0.4], default: ("tsp", 1)),
        f("Garlic", ["garlic"], 149, 6.4, 33, 0.5, ["piece": 3, "clove": 3], default: ("clove", 2)),

        // Snacks and treats
        f("Almonds", ["almonds", "nuts", "cashews", "walnuts", "peanuts", "mixed nuts"], 579, 21, 22, 50, ["piece": 1.2, "cup": 143, "handful": 28], default: ("oz", 1)),
        f("Potato chips", ["chips", "potato chips", "tortilla chips"], 536, 7, 53, 35, ["serving": 28, "cup": 25, "bag": 28], default: ("oz", 1)),
        f("Dark chocolate", ["chocolate", "dark chocolate"], 546, 4.9, 61, 31, ["piece": 10, "bar": 43], default: ("oz", 1)),
        f("Protein bar", ["protein bar"], 370, 33, 37, 13, ["piece": 60, "bar": 60], default: ("piece", 1)),
        f("Cookie", ["cookie", "cookies"], 488, 5, 64, 24, ["piece": 30], default: ("piece", 1)),

        // Mixed dishes
        f("Sushi roll", ["sushi", "sushi roll", "california roll", "spicy tuna roll", "maki", "roll"], 140, 4.5, 22, 3.5, ["piece": 32, "roll": 256], default: ("piece", 6)),
        f("Nigiri", ["nigiri"], 150, 7, 25, 2, ["piece": 40], default: ("piece", 2)),
        f("Sashimi", ["sashimi"], 130, 22, 0, 4, ["piece": 28], default: ("piece", 5)),
        f("Pizza", ["pizza", "pizza slice", "cheese pizza", "pepperoni pizza"], 266, 11, 33, 10, ["slice": 107, "piece": 107], default: ("slice", 2)),
        f("Burrito", ["burrito"], 206, 9, 25, 7, ["piece": 400], default: ("piece", 1)),
        f("Taco", ["taco", "tacos"], 217, 9, 20, 11, ["piece": 78], default: ("piece", 2)),

        // Drinks
        f("Beer", ["beer"], 43, 0.5, 3.6, 0, ["can": 355, "bottle": 355, "piece": 355, "pint": 473], default: ("can", 1)),
        f("Light beer", ["light beer", "michelob ultra", "bud light", "coors light"], 29, 0.2, 1.6, 0, ["can": 355, "bottle": 355, "piece": 355], default: ("can", 1)),
        f("Wine", ["wine", "red wine", "white wine"], 83, 0.1, 2.6, 0, ["glass": 148, "piece": 148], default: ("glass", 1)),
        f("Soda", ["soda", "coke", "pepsi", "sprite"], 41, 0, 10.6, 0, ["can": 368, "piece": 368], default: ("can", 1)),
        f("Coffee", ["coffee", "black coffee", "espresso", "americano", "diet soda", "diet coke", "water", "tea"], 1, 0.1, 0, 0, ["cup": 237], default: ("cup", 1)),
        f("Orange juice", ["orange juice", "juice", "oj"], 45, 0.7, 10, 0.2, ["cup": 248, "glass": 248], default: ("cup", 1))
    ]

    /// The food whose name or alias best matches `text` (longest match wins:
    /// "hot honey" over "honey", "brown rice" over "rice").
    static func match(_ text: String) -> FoodFacts? {
        let t = " " + normalize(text) + " "
        var best: (FoodFacts, Int)?
        for food in foods {
            for alias in [food.name.lowercased()] + food.aliases {
                let a = normalize(alias)
                guard !a.isEmpty, t.contains(" " + a + " ") || t.contains(" " + a + "s ") else { continue }
                if a.count > (best?.1 ?? 0) { best = (food, a.count) }
            }
        }
        return best?.0
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }
}
