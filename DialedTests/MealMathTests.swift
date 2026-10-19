//
//  MealMathTests.swift
//  DialedTests
//
//  Meal estimates come from the food table, not a model's arithmetic:
//  the broccoli and sushi cases that the on-device model got 3–5× too
//  high, amounts and sizes, and dishes it can't price get flagged.
//

import XCTest
@testable import Dialed

final class MealMathTests: XCTestCase {

    func testBroccoliWithOilAndHotHoney() {
        let r = MealMath.estimate("Broccoli with olive oil, salt and pepper and Mike’s hot honey")
        XCTAssertTrue(r.isComplete)
        XCTAssertEqual(r.calories, 90, accuracy: 10)          // was 350 from the model
        XCTAssertEqual(Set(r.parts.map(\.name)), ["Broccoli", "Olive oil", "Seasoning", "Hot honey"])
    }

    func testSushiPieces() {
        let r = MealMath.estimate("5 pieces of a sushi roll")
        XCTAssertEqual(r.calories, 224, accuracy: 15)         // was 1,250 from the model
        XCTAssertEqual(MealMath.estimate("a california roll").parts.first?.amount, "1 roll")
    }

    func testAmountsUnitsAndSizes() {
        let r = MealMath.estimate("8 oz grilled chicken, 1 cup rice and broccoli")
        XCTAssertEqual(r.parts.first { $0.name == "Chicken breast" }?.calories ?? 0, 374, accuracy: 2)
        XCTAssertEqual(r.calories, 610, accuracy: 10)
        XCTAssertEqual(MealMath.estimate("half an avocado").parts.first?.amount, "½ piece")
        XCTAssertGreaterThan(MealMath.estimate("3 large eggs").calories, MealMath.estimate("3 eggs").calories)
    }

    func testDishesItCantPriceAreFlagged() {
        let r = MealMath.estimate("chipotle bowl double chicken")
        XCTAssertFalse(r.isComplete)
        XCTAssertFalse(r.unknown.isEmpty)
    }

    func testScalingAPortion() {
        let part = MealMath.estimate("1 cup rice").parts[0].scaled(2)
        XCTAssertEqual(part.amount, "2 cups")
        XCTAssertEqual(part.calories, 411, accuracy: 2)
    }

    func testModelNumbersAreReconciledWithMacros() {
        // 1,250 "calories" for 15 g protein, 180 g carbs, 10 g fat doesn't add up.
        XCTAssertEqual(MealMath.reconciled(calories: 1_250, protein: 15, carbs: 180, fat: 10), 870, accuracy: 1)
        XCTAssertEqual(MealMath.reconciled(calories: 420, protein: 30, carbs: 40, fat: 15), 420)
    }
}
