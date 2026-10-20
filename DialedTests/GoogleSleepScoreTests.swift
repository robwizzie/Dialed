//
//  GoogleSleepScoreTests.swift
//  DialedTests
//
//  Google doesn't document where its sleep score lives, so Dialed accepts
//  the likely shapes: a number on the night or its summary, as a string,
//  or as an object.
//

import XCTest
@testable import Dialed

final class GoogleSleepScoreTests: XCTestCase {

    private func sleep(_ json: String) throws -> GHDataPoint.Sleep? {
        try JSONDecoder().decode(GHDataPoint.self, from: Data(json.utf8)).sleep
    }

    func testScoreShapes() throws {
        XCTAssertEqual(try sleep(#"{"sleep":{"sleepScore":87}}"#)?.vendorScore, 87)
        XCTAssertEqual(try sleep(#"{"sleep":{"summary":{"score":"79"}}}"#)?.vendorScore, 79)
        XCTAssertEqual(try sleep(#"{"sleep":{"sleepScore":{"overallScore":91.4}}}"#)?.vendorScore, 91)
        XCTAssertEqual(try sleep(#"{"sleep":{"overallScore":{"value":66}}}"#)?.vendorScore, 66)
    }

    func testNoScoreOrNonsense() throws {
        XCTAssertNil(try sleep(#"{"sleep":{"summary":{"minutesAsleep":"420"}}}"#)?.vendorScore)
        XCTAssertNil(try sleep(#"{"sleep":{"score":0}}"#)?.vendorScore)
        XCTAssertNil(try sleep(#"{"sleep":{"score":{"stages":[1,2]}}}"#)?.vendorScore)
    }

    func testDailySleepScoreType() throws {
        let p = try JSONDecoder().decode(GHDataPoint.self, from: Data(#"{"dailySleepScore":{"date":{"year":2026,"month":10,"day":20},"overallScore":84}}"#.utf8))
        XCTAssertEqual(p.dailySleepScore?.vendorScore, 84)
    }
}
