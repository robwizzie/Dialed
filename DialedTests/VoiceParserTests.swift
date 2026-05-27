//
//  VoiceParserTests.swift
//  DialedTests
//
//  Exercises every per-kind matcher with the kinds of phrasings a real
//  user would say. Parser is pure so no fixtures needed.
//

import XCTest
@testable import Dialed

final class VoiceParserTests: XCTestCase {

    private let fixedTime = Date(timeIntervalSince1970: 1_716_624_000)

    // MARK: - Water

    func testParse_water_keywordOnly() {
        let event = VoiceParser.parse("log 16 ounces of water", at: fixedTime)
        XCTAssertEqual(event?.kind, .water)
        XCTAssertEqual(event?.value, 16)
        XCTAssertEqual(event?.unit, "oz")
        XCTAssertEqual(event?.source, .voice)
    }

    func testParse_water_drankPhrasing() {
        let event = VoiceParser.parse("drank 24 oz", at: fixedTime)
        XCTAssertEqual(event?.kind, .water)
        XCTAssertEqual(event?.value, 24)
    }

    func testParse_water_defaultsTo8WhenNoNumber() {
        let event = VoiceParser.parse("had some water", at: fixedTime)
        XCTAssertEqual(event?.kind, .water)
        XCTAssertEqual(event?.value, 8)
    }

    // MARK: - Caffeine

    func testParse_caffeine_coffeeWithMG() {
        let event = VoiceParser.parse("just had 95 mg of coffee", at: fixedTime)
        XCTAssertEqual(event?.kind, .caffeine)
        XCTAssertEqual(event?.value, 95)
        XCTAssertEqual(event?.subtype, "coffee")
    }

    func testParse_caffeine_espressoSubtype() {
        let event = VoiceParser.parse("double espresso", at: fixedTime)
        XCTAssertEqual(event?.kind, .caffeine)
        XCTAssertEqual(event?.subtype, "espresso")
    }

    func testParse_caffeine_preworkout() {
        let event = VoiceParser.parse("took my preworkout, 200mg", at: fixedTime)
        XCTAssertEqual(event?.kind, .caffeine)
        XCTAssertEqual(event?.subtype, "preworkout")
        XCTAssertEqual(event?.value, 200)
    }

    func testParse_caffeine_defaultsTo95WhenNoNumber() {
        let event = VoiceParser.parse("coffee", at: fixedTime)
        XCTAssertEqual(event?.kind, .caffeine)
        XCTAssertEqual(event?.value, 95)
    }

    // MARK: - Alcohol

    func testParse_alcohol_singleBeer() {
        let event = VoiceParser.parse("had 1 beer", at: fixedTime)
        XCTAssertEqual(event?.kind, .alcohol)
        XCTAssertEqual(event?.value, 1)
    }

    func testParse_alcohol_twoCocktails() {
        let event = VoiceParser.parse("2 cocktails at dinner", at: fixedTime)
        XCTAssertEqual(event?.kind, .alcohol)
        XCTAssertEqual(event?.value, 2)
    }

    func testParse_alcohol_doesNotMatchDrankWater() {
        // "drank water" should NOT become an alcohol event.
        let event = VoiceParser.parse("drank some water", at: fixedTime)
        XCTAssertEqual(event?.kind, .water,
                       "Water keyword should dominate the alcohol fallback")
    }

    // MARK: - Meal

    func testParse_meal_caloriesAndProtein() {
        let event = VoiceParser.parse("breakfast 600 calories 35g protein", at: fixedTime)
        XCTAssertEqual(event?.kind, .meal)
        XCTAssertEqual(event?.subtype, "breakfast")
        XCTAssertEqual(event?.value, 600)
        XCTAssertEqual(event?.secondaryValue, 35)
    }

    func testParse_meal_caloriesOnly() {
        let event = VoiceParser.parse("had 800 kcal lunch", at: fixedTime)
        XCTAssertEqual(event?.kind, .meal)
        XCTAssertEqual(event?.subtype, "lunch")
        XCTAssertEqual(event?.value, 800)
    }

    func testParse_meal_genericMealWord() {
        let event = VoiceParser.parse("just ate dinner", at: fixedTime)
        XCTAssertEqual(event?.kind, .meal)
        XCTAssertEqual(event?.subtype, "dinner")
    }

    // MARK: - Mood / energy

    func testParse_mood_withRating() {
        let event = VoiceParser.parse("mood 4", at: fixedTime)
        XCTAssertEqual(event?.kind, .mood)
        XCTAssertEqual(event?.value, 4)
    }

    func testParse_mood_clampsAboveFive() {
        let event = VoiceParser.parse("feeling 9 out of 10", at: fixedTime)
        XCTAssertEqual(event?.kind, .mood)
        XCTAssertEqual(event?.value, 5, "Ratings >5 should clamp to 5")
    }

    func testParse_energy_withRating() {
        let event = VoiceParser.parse("energy 2", at: fixedTime)
        XCTAssertEqual(event?.kind, .energy)
        XCTAssertEqual(event?.value, 2)
    }

    // MARK: - Workout

    func testParse_workout_pushDay() {
        let event = VoiceParser.parse("push day 45 minutes", at: fixedTime)
        XCTAssertEqual(event?.kind, .workout)
        XCTAssertEqual(event?.subtype, "push")
        XCTAssertEqual(event?.value, 45)
    }

    func testParse_workout_ranDistance() {
        let event = VoiceParser.parse("ran for 30 minutes", at: fixedTime)
        XCTAssertEqual(event?.kind, .workout)
        XCTAssertEqual(event?.subtype, "cardio")
        XCTAssertEqual(event?.value, 30)
    }

    // MARK: - Fallback

    func testParse_fallbackToNote() {
        let event = VoiceParser.parse("remember to call mom tomorrow", at: fixedTime)
        XCTAssertEqual(event?.kind, .note)
        XCTAssertEqual(event?.text, "remember to call mom tomorrow")
    }

    func testParse_emptyStringReturnsNil() {
        XCTAssertNil(VoiceParser.parse("", at: fixedTime))
        XCTAssertNil(VoiceParser.parse("   ", at: fixedTime))
    }

    // MARK: - Sourcing

    func testParse_alwaysTagsSourceAsVoice() {
        let utterances = [
            "16 oz water",
            "coffee 95mg",
            "1 beer",
            "lunch 600 calories",
            "mood 4",
            "energy 3",
            "push day 45 minutes",
            "just a stray thought"
        ]
        for utterance in utterances {
            let event = VoiceParser.parse(utterance, at: fixedTime)
            XCTAssertEqual(event?.source, .voice,
                           "Expected voice source for: \(utterance)")
        }
    }
}
