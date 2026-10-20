//
//  PhotoStatsTests.swift
//  DialedTests
//
//  Each progress photo picks up the trend weight, scale reading and body
//  fat around its date, and two photos read as one plain delta line.
//

import XCTest
@testable import Dialed

final class PhotoStatsTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func day(_ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    private var series: [WeightChallengeEngine.DailyWeight] {
        let readings = [(9, 1, 210.0), (9, 2, 209.4), (9, 5, 209.0), (10, 10, 203.0), (10, 12, 202.2), (10, 13, 201.6)]
            .map { WeightReading(date: day($0.0, $0.1), pounds: $0.2, source: .manual) }
        return WeightChallengeEngine.dailySeries(readings, calendar: calendar)
    }

    private let fat = [(9, 3, 0.33), (10, 14, 0.309), (8, 1, 0.35)]

    private var fatReadings: [PhotoStats.Reading] {
        fat.map { PhotoStats.Reading(date: day($0.0, $0.1), value: $0.2) }
    }

    func testStatsAroundEachPhoto() {
        let first = PhotoStats.stats(on: day(9, 1, 9), photoWeight: nil, series: series, bodyFat: fatReadings, calendar: calendar)
        XCTAssertEqual(first.trend, 210)
        XCTAssertEqual(first.scale, 210)          // that day's weigh-in
        XCTAssertEqual(first.bodyFat, 0.33)       // two days later, within ±3

        let latest = PhotoStats.stats(on: day(10, 13, 9), photoWeight: 201.8, series: series, bodyFat: fatReadings, calendar: calendar)
        XCTAssertEqual(latest.scale, 201.8)       // the weight saved with the photo wins
        XCTAssertEqual(latest.trend ?? 0, 202.39, accuracy: 0.01)
        XCTAssertEqual(latest.bodyFat, 0.309)
    }

    func testNothingNearbyMeansNoNumbers() {
        let lonely = PhotoStats.stats(on: day(12, 25), photoWeight: nil, series: series, bodyFat: fatReadings, calendar: calendar)
        XCTAssertTrue(lonely.isEmpty)
    }

    func testDeltaSummary() {
        let a = PhotoStats.stats(on: day(9, 1, 9), photoWeight: nil, series: series, bodyFat: fatReadings, calendar: calendar)
        let b = PhotoStats.stats(on: day(10, 13, 9), photoWeight: 201.8, series: series, bodyFat: fatReadings, calendar: calendar)
        let delta = PhotoStats.delta(from: a, at: day(9, 1), to: b, at: day(10, 13), calendar: calendar)
        XCTAssertEqual(delta.days, 42)
        XCTAssertEqual(delta.summary, "−7.6 lb trend · −2.1% body fat · 6 weeks")
    }

    func testFormatting() {
        XCTAssertEqual(PhotoStats.span(0), "same day")
        XCTAssertEqual(PhotoStats.span(9), "1 week 2 days")
        XCTAssertEqual(PhotoStats.span(42), "6 weeks")
        XCTAssertEqual(PhotoStats.signed(-0.04), "±0.0")
        XCTAssertEqual(PhotoStats.percent(0.322), "32.2%")
    }
}
