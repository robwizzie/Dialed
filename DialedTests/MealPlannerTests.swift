//
//  MealPlannerTests.swift
//  DialedTests
//
//  Restaurant picks fit what's left of the day, lead with protein, and
//  the menu guide finds chains however you type them.
//

import XCTest
@testable import Dialed

final class MealPlannerTests: XCTestCase {

    func testFindsChainsHoweverTyped() {
        XCTAssertEqual(RestaurantMenus.find("chickfila")?.name, "Chick-fil-A")
        XCTAssertEqual(RestaurantMenus.find("McD")?.name, "McDonald's")
        XCTAssertEqual(RestaurantMenus.find("panera bread")?.name, "Panera")
        XCTAssertNil(RestaurantMenus.find("Grandma's Diner"))
    }

    func testBudgetSavesRoomForLaterMeals() {
        let lunch = MealPlanner.Budget.forNow(caloriesLeft: 1_400, proteinLeft: 120, hour: 13)
        XCTAssertEqual(lunch.calories, 700)
        XCTAssertEqual(lunch.protein, 60)
        let last = MealPlanner.Budget.forNow(caloriesLeft: 800, proteinLeft: 60, hour: 13, lastMeal: true)
        XCTAssertEqual(last.calories, 760, accuracy: 0.1)
    }

    func testPicksFitTheBudgetAndLeadWithProtein() {
        let menu = RestaurantMenus.find("Chipotle")!.items
        let budget = MealPlanner.Budget.forNow(caloriesLeft: 1_400, proteinLeft: 120, hour: 13)
        let picks = MealPlanner.picks(menu: menu, budget: budget)
        XCTAssertFalse(picks.isEmpty)
        XCTAssertEqual(picks.first?.kind, .protein)
        for p in picks { XCTAssertLessThanOrEqual(p.calories, budget.calories * 1.08) }
        XCTAssertGreaterThanOrEqual(picks.first?.protein ?? 0, 60)
    }

    func testNothingFitsFallsBackToLightest() {
        let menu = [MenuItem(name: "Big burger", calories: 900, protein: 40, carbs: 60, fat: 50),
                    MenuItem(name: "Huge burger", calories: 1_300, protein: 60, carbs: 80, fat: 80)]
        let picks = MealPlanner.picks(menu: menu, budget: .init(caloriesLeft: 300, proteinLeft: 30, share: 1))
        XCTAssertEqual(picks.map(\.kind), [.light])
        XCTAssertEqual(picks.first?.items.first?.name, "Big burger")
    }
}
