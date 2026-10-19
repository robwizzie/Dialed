//
//  GoogleHealthDTOTests.swift
//  DialedTests
//
//  Wire-format decoding for the Google Health API v4: int64-as-string,
//  RFC 3339 with nanoseconds, daily roll-ups, sleep stages, and the
//  reversed-client-ID redirect scheme.
//

import XCTest
@testable import Dialed

final class GoogleHealthDTOTests: XCTestCase {

    func testReversedClientID() {
        XCTAssertEqual(
            GoogleHealthConfig.reversedClientID("1234-abcd.apps.googleusercontent.com"),
            "com.googleusercontent.apps.1234-abcd"
        )
        XCTAssertNil(GoogleHealthConfig.reversedClientID("23ABCD"))
        XCTAssertNil(GoogleHealthConfig.reversedClientID(".apps.googleusercontent.com"))
    }

    func testTimeParsingHandlesNanosAndOffsets() {
        let a = GHTime.parse("2026-10-18T06:12:30.123456789Z")
        let b = GHTime.parse("2026-10-18T06:12:30Z")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        let c = GHTime.parse("2026-10-18T02:12:30-04:00")
        XCTAssertEqual(c, b)
        XCTAssertNil(GHTime.parse(nil))
        XCTAssertNil(GHTime.parse("not a date"))
        XCTAssertEqual(GHTime.rfc3339(b!), "2026-10-18T06:12:30Z")
    }

    func testDecodesWeightHeartRateAndDailyVitals() throws {
        let json = """
        {"dataPoints":[
          {"weight":{"weightGrams":85048.0,"sampleTime":{"physicalTime":"2026-10-18T11:02:00Z","utcOffset":"-14400s"}}},
          {"heartRate":{"beatsPerMinute":"72","sampleTime":{"physicalTime":"2026-10-18T17:20:00.5Z"}}},
          {"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":18},"beatsPerMinute":"58"}},
          {"dailyHeartRateVariability":{"date":{"year":2026,"month":10,"day":18},"averageHeartRateVariabilityMilliseconds":41.5}},
          {"dailyOxygenSaturation":{"date":{"year":2026,"month":10,"day":18},"averagePercentage":96.4,"lowerBoundPercentage":94,"upperBoundPercentage":98}}
        ],"nextPageToken":""}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(GHListResponse.self, from: json)
        let points = try XCTUnwrap(resp.dataPoints)
        XCTAssertEqual(points.count, 5)
        XCTAssertEqual(points[0].weight?.weightGrams ?? 0, 85048, accuracy: 0.1)
        XCTAssertEqual(points[1].heartRate?.beatsPerMinute?.value, 72)
        XCTAssertNotNil(GHTime.parse(points[1].heartRate?.sampleTime?.physicalTime))
        XCTAssertEqual(points[2].dailyRestingHeartRate?.beatsPerMinute?.value, 58)
        XCTAssertEqual(points[2].dailyRestingHeartRate?.date?.iso, "2026-10-18")
        XCTAssertEqual(points[3].dailyHeartRateVariability?.averageHeartRateVariabilityMilliseconds, 41.5)
        XCTAssertEqual(points[4].dailyOxygenSaturation?.averagePercentage, 96.4)
    }

    func testDecodesSleepStages() throws {
        let json = """
        {"dataPoints":[{"name":"users/me/dataTypes/sleep/dataPoints/abc",
          "sleep":{"interval":{"startTime":"2026-10-18T03:30:00Z","endTime":"2026-10-18T11:00:00Z"},
                   "metadata":{"mainSleep":true,"nap":false},
                   "summary":{"minutesAsleep":"410","minutesAwake":"40","minutesInSleepPeriod":"450",
                              "stagesSummary":[{"type":"DEEP","minutes":"70","count":"4"},{"type":"REM","minutes":"95"},{"type":"LIGHT","minutes":"245"}]}}}]}
        """.data(using: .utf8)!
        let sleep = try XCTUnwrap(JSONDecoder().decode(GHListResponse.self, from: json).dataPoints?.first?.sleep)
        XCTAssertEqual(sleep.summary?.minutesAsleep?.value, 410)
        XCTAssertEqual(sleep.minutes(of: "DEEP"), 70)
        XCTAssertEqual(sleep.minutes(of: "REM"), 95)
        XCTAssertNil(sleep.minutes(of: "AWAKE"))
        XCTAssertEqual(sleep.metadata?.mainSleep, true)
    }

    func testDailyRollUpRoundTrip() throws {
        let request = GHDailyRollUpRequest(
            range: .init(start: GHCivilDateTime(date: GHDate(year: 2026, month: 10, day: 12)),
                         end: GHCivilDateTime(date: GHDate(year: 2026, month: 10, day: 19))),
            windowSizeDays: 1
        )
        let body = String(data: try JSONEncoder().encode(request), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"windowSizeDays\":1"))
        XCTAssertTrue(body.contains("\"year\":2026"))

        let json = """
        {"rollupDataPoints":[
          {"civilStartTime":{"date":{"year":2026,"month":10,"day":18}},"steps":{"countSum":"8420"}},
          {"civilStartTime":{"date":{"year":2026,"month":10,"day":18}},"hydrationLog":{"amountConsumed":{"millilitersSum":1892.7}}}
        ]}
        """.data(using: .utf8)!
        let points = try XCTUnwrap(JSONDecoder().decode(GHDailyRollUpResponse.self, from: json).rollupDataPoints)
        XCTAssertEqual(points[0].steps?.countSum?.value, 8420)
        XCTAssertEqual(points[1].hydrationLog?.amountConsumed?.millilitersSum ?? 0, 1892.7, accuracy: 0.01)
    }

    func testGHIntAcceptsNumbersToo() throws {
        let v = try JSONDecoder().decode([GHInt].self, from: "[5, \"6\", 7.0]".data(using: .utf8)!)
        XCTAssertEqual(v.map(\.value), [5, 6, 7])
    }
}
