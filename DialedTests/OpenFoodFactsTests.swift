//
//  OpenFoodFactsTests.swift
//  DialedTests
//
//  Barcode lookups: the API's JSON (numbers or strings, kJ-only labels,
//  missing products) parses into the nutrients we log, and servings /
//  grams scale them the way the label says.
//

import XCTest
@testable import Dialed

final class OpenFoodFactsTests: XCTestCase {

    private func json(_ s: String) -> Data { Data(s.utf8) }

    private let barJSON = """
    {"code":"0123456789012","status":1,"product":{
      "product_name":"Protein Bar","brands":"Quest, Quest Nutrition",
      "serving_size":"1 bar (60 g)","serving_quantity":"60",
      "nutriments":{"energy-kcal_100g":350,"energy-kcal_serving":210,
        "proteins_100g":33.3,"proteins_serving":"20",
        "carbohydrates_100g":40,"carbohydrates_serving":24,
        "fat_100g":13.3,"fat_serving":8}}}
    """

    func testParsesServingAndPer100g() throws {
        let p = try OpenFoodFacts.parse(json(barJSON), code: "0123456789012")
        XCTAssertEqual(p.name, "Protein Bar")
        XCTAssertEqual(p.brand, "Quest")
        XCTAssertEqual(p.displayName, "Quest Protein Bar")
        XCTAssertEqual(p.servingSize, "1 bar (60 g)")
        XCTAssertEqual(p.servingGrams, 60)
        XCTAssertEqual(p.perServing.calories, 210)
        XCTAssertEqual(p.perServing.protein, 20)
        XCTAssertEqual(p.per100g.calories, 350)
        XCTAssertEqual(p.per100g.fat, 13.3)
        XCTAssertTrue(p.supportsServings)
        XCTAssertTrue(p.supportsGrams)
        XCTAssertEqual(p.defaultPortion, .servings(1))
    }

    func testServingMathPrefersLabelServing() throws {
        let p = try OpenFoodFacts.parse(json(barJSON), code: "1")
        let two = try XCTUnwrap(p.nutrients(for: .servings(2)))
        XCTAssertEqual(two.calories, 420)
        XCTAssertEqual(two.protein, 40)
        XCTAssertEqual(two.carbs, 48)
        XCTAssertEqual(two.fat, 16)
    }

    func testGramMathUsesPer100g() throws {
        let p = try OpenFoodFacts.parse(json(barJSON), code: "1")
        let g = try XCTUnwrap(p.nutrients(for: .grams(30)))
        XCTAssertEqual(g.calories ?? 0, 105, accuracy: 0.001)
        XCTAssertEqual(g.protein ?? 0, 9.99, accuracy: 0.001)
    }

    func testServingsFallBackToPer100gTimesServingWeight() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Greek Yogurt","serving_quantity":170,
         "nutriments":{"energy-kcal_100g":59,"proteins_100g":10.3}}}
        """)
        let p = try OpenFoodFacts.parse(data, code: "2")
        let one = try XCTUnwrap(p.nutrients(for: .servings(1)))
        XCTAssertEqual(one.calories ?? 0, 100.3, accuracy: 0.001)
        XCTAssertEqual(one.protein ?? 0, 17.51, accuracy: 0.001)
        XCTAssertNil(one.carbs)
    }

    func testGramsFallBackToServingWhenNoPer100g() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Shake","serving_quantity":"300",
         "nutriments":{"energy-kcal_serving":160,"proteins_serving":30}}}
        """)
        let p = try OpenFoodFacts.parse(data, code: "3")
        let half = try XCTUnwrap(p.nutrients(for: .grams(150)))
        XCTAssertEqual(half.calories, 80)
        XCTAssertEqual(half.protein, 15)
    }

    func testOnlyPer100gWithoutServingWeightStartsOnGrams() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Oats","nutriments":{"energy-kcal_100g":379,"proteins_100g":13}}}
        """)
        let p = try OpenFoodFacts.parse(data, code: "4")
        XCTAssertFalse(p.supportsServings)
        XCTAssertNil(p.nutrients(for: .servings(1)))
        XCTAssertEqual(p.defaultPortion, .grams(100))
        XCTAssertEqual(p.nutrients(for: .grams(40))?.calories ?? 0, 151.6, accuracy: 0.001)
    }

    func testKilojouleOnlyLabelsConvert() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Biscuit","nutriments":{"energy-kj_100g":2092}}}
        """)
        let p = try OpenFoodFacts.parse(data, code: "5")
        XCTAssertEqual(p.per100g.calories ?? 0, 500, accuracy: 0.01)
    }

    func testMissingProductThrowsNotFound() {
        let data = json(#"{"code":"999","status":0,"status_verbose":"product not found"}"#)
        XCTAssertThrowsError(try OpenFoodFacts.parse(data, code: "999")) { error in
            XCTAssertEqual(error as? OpenFoodFacts.LookupError, .notFound)
        }
    }

    func testProductWithoutCaloriesThrowsNoNutrition() {
        let data = json(#"{"status":1,"product":{"product_name":"Mystery","nutriments":{}}}"#)
        XCTAssertThrowsError(try OpenFoodFacts.parse(data, code: "6")) { error in
            XCTAssertEqual(error as? OpenFoodFacts.LookupError, .noNutrition)
        }
    }

    func testBlankNameFallsBackToBrand() throws {
        let data = json(#"{"status":1,"product":{"product_name":" ","brands":"Fairlife","nutriments":{"energy-kcal_serving":150}}}"#)
        let p = try OpenFoodFacts.parse(data, code: "7")
        XCTAssertEqual(p.name, "Fairlife")
        XCTAssertEqual(p.displayName, "Fairlife")
    }

    func testURLKeepsDigitsOnly() {
        XCTAssertEqual(
            OpenFoodFacts.url(for: " 0-12345 67890 5 ")?.absoluteString,
            "https://world.openfoodfacts.org/api/v2/product/012345678905.json?fields=\(OpenFoodFacts.fields)"
        )
        XCTAssertNil(OpenFoodFacts.url(for: "abc"))
        XCTAssertNil(OpenFoodFacts.url(for: "123456789012345"))
    }
}
