//
//  WeekMealPlannerTests.swift
//  DialedTests
//
//  A week of go-to meals lands on the calorie target with plenty of
//  protein, prices every meal from the food table, rotates, swaps, and
//  adds up a sensible grocery list.
//

import XCTest
@testable import Dialed

final class WeekMealPlannerTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testEveryDayFitsTheTargetAndProtein() {
        let week = WeekMealPlanner.week(start: start, calories: 2_590, protein: 170)
        XCTAssertEqual(week.days.count, 7)
        for day in week.days {
            XCTAssertEqual(day.meals.map(\.slot), WeekMealPlanner.Slot.allCases)
            XCTAssertEqual(day.calories, 2_590, accuracy: 2_590 * 0.05)
            XCTAssertGreaterThanOrEqual(day.protein, 170 * 0.9)
        }
        // Rotates instead of eating the same lunch every day.
        XCTAssertGreaterThan(Set(week.days.map { $0.meals[1].templateID }).count, 1)
    }

    func testSmallerBudgetStillHitsProtein() {
        let week = WeekMealPlanner.week(start: start, calories: 1_900, protein: 160)
        for day in week.days {
            XCTAssertEqual(day.calories, 1_900, accuracy: 1_900 * 0.06)
            XCTAssertGreaterThanOrEqual(day.protein, 160 * 0.9)
        }
    }

    func testMealsArePricedByTheTable() {
        let bowl = WeekMealPlanner.library.first { $0.id == "chicken-bowl" }!
        let meal = WeekMealPlanner.meal(bowl)
        // 170 g chicken (165/100 g) + 180 g rice (130) + 100 g broccoli (34) + 15 g soy sauce.
        let expected = 1.7 * 165 + 1.8 * 130 + (NutritionTable.foods.first { $0.name == "Broccoli" }!.calories)
            + 0.15 * (NutritionTable.foods.first { $0.name == "Soy sauce" }!.calories)
        XCTAssertEqual(meal.calories, expected.rounded(), accuracy: 1)
        XCTAssertEqual(WeekMealPlanner.meal(bowl, scale: 2).calories, (expected * 2).rounded(), accuracy: 2)
        for t in WeekMealPlanner.library {
            for i in t.ingredients { XCTAssertNotNil(WeekMealPlanner.food(i.food), "\(i.food) isn't in the table") }
        }
    }

    func testFavoritesRankFirstAndSwapMovesOn() {
        let liked = WeekMealPlanner.preferredFoods(fromNames: ["deli turkey", "tortilla", "cheddar"])
        XCTAssertEqual(WeekMealPlanner.ranked(.lunch, preferred: liked).first?.id, "turkey-wrap")

        let week = WeekMealPlanner.week(start: start, calories: 2_400, protein: 170)
        let before = week.days[0].meals.first { $0.slot == .dinner }!
        let after = WeekMealPlanner.swap(week, day: 0, slot: .dinner).days[0].meals.first { $0.slot == .dinner }!
        XCTAssertNotEqual(before.templateID, after.templateID)
        XCTAssertEqual(after.calories, 2_400 * WeekMealPlanner.Slot.dinner.share, accuracy: 60)
    }

    func testGroceriesAddUpInShoppingUnits() {
        let week = WeekMealPlanner.week(start: start, calories: 2_590, protein: 170)
        let list = WeekMealPlanner.groceries(week)
        XCTAssertEqual(Set(list.map(\.aisle)).isSubset(of: Set(WeekMealPlanner.aisles)), true)
        XCTAssertEqual(list.map(\.aisle), list.map(\.aisle).sorted { WeekMealPlanner.aisles.firstIndex(of: $0)! < WeekMealPlanner.aisles.firstIndex(of: $1)! })
        XCTAssertEqual(WeekMealPlanner.shoppingAmount("Egg", grams: 1_000), "20 eggs")
        XCTAssertEqual(WeekMealPlanner.shoppingAmount("White rice", grams: 2_000), "4 cups (dry)")
        XCTAssertEqual(WeekMealPlanner.shoppingAmount("Chicken breast", grams: 1_200), "2¾ lb")
        XCTAssertEqual(WeekMealPlanner.amountText(.init(food: "Chicken breast", grams: 170)), "6 oz chicken breast")
        XCTAssertEqual(WeekMealPlanner.amountText(.init(food: "Egg", grams: 150)), "3 eggs")
    }
}
