//
//  SkincareMatcherTests.swift
//  DialedTests
//
//  The skincare cleanup removes face-wash tasks and nothing else.
//

import XCTest
@testable import Dialed

final class SkincareMatcherTests: XCTestCase {

    func testFindsSkincareByKindTypeOrWording() {
        XCTAssertTrue(SkincareMatcher.isSkincare(kindRaw: "skincare", title: "Anything"))
        XCTAssertTrue(SkincareMatcher.isSkincare(kindRaw: "routine", title: "PM skincare"))
        XCTAssertTrue(SkincareMatcher.isSkincare(kindRaw: "routine", title: "Night routine", detail: "Wash face + CeraVe PM"))
        XCTAssertTrue(SkincareMatcher.isSkincare(checklistType: "AM Skincare", customTitle: nil, customDescription: nil))
        XCTAssertTrue(SkincareMatcher.isSkincare(checklistType: "custom", customTitle: "Sunscreen", customDescription: nil))
        XCTAssertTrue(SkincareMatcher.matches("SPF 30 before the walk"))
    }

    func testLeavesEverythingElseAlone() {
        XCTAssertFalse(SkincareMatcher.isSkincare(kindRaw: "supplement", title: "Creatine", detail: "5g"))
        XCTAssertFalse(SkincareMatcher.isSkincare(kindRaw: "windDown", title: "Wind down", detail: "Dim lights, no scrolling"))
        XCTAssertFalse(SkincareMatcher.isSkincare(checklistType: "Lunch Vitamins", customTitle: nil, customDescription: nil))
        XCTAssertFalse(SkincareMatcher.matches("Wash the car"))
        XCTAssertFalse(SkincareMatcher.matches("Inspection"))
        XCTAssertFalse(SkincareMatcher.matches(nil))
    }
}
