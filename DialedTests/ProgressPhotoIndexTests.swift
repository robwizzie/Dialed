//
//  ProgressPhotoIndexTests.swift
//  DialedTests
//
//  The progress-photo index keeps photos in order, groups them by week,
//  finds the ghost photo and round-trips through JSON.
//

import XCTest
@testable import Dialed

final class ProgressPhotoIndexTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    func testAddKeepsOldestFirstAndReplacesSameID() {
        var index = ProgressPhotoIndex()
        let b = ProgressPhotoEntry(date: date(10, 11), weightLbs: 210)
        let a = ProgressPhotoEntry(date: date(10, 4), weightLbs: 214)
        index.add(b)
        index.add(a)
        XCTAssertEqual(index.entries.map(\.id), [a.id, b.id])
        XCTAssertEqual(index.first, a)
        XCTAssertEqual(index.latest, b)

        var edited = b
        edited.note = "after"
        index.add(edited)
        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(index.latest?.note, "after")
    }

    func testRemoveAndUpdate() {
        let a = ProgressPhotoEntry(date: date(10, 4))
        var index = ProgressPhotoIndex(entries: [a])
        index.update(id: a.id, weightLbs: 212.4, note: "Sunday")
        XCTAssertEqual(index.entry(id: a.id)?.weightLbs, 212.4)
        XCTAssertEqual(index.remove(id: a.id)?.id, a.id)
        XCTAssertNil(index.remove(id: a.id))
        XCTAssertTrue(index.entries.isEmpty)
    }

    func testGhostIsLatestBefore() {
        let a = ProgressPhotoEntry(date: date(10, 4))
        let b = ProgressPhotoEntry(date: date(10, 11))
        let index = ProgressPhotoIndex(entries: [b, a])
        XCTAssertEqual(index.latest(before: date(10, 18)), b)
        XCTAssertEqual(index.latest(before: date(10, 11)), a)
        XCTAssertNil(index.latest(before: date(10, 1)))
    }

    func testWeeksNewestFirst() {
        let index = ProgressPhotoIndex(entries: [
            ProgressPhotoEntry(date: date(10, 4)),      // Sun, week of Oct 4
            ProgressPhotoEntry(date: date(10, 6)),      // Tue, same week
            ProgressPhotoEntry(date: date(10, 11))      // Sun, next week
        ])
        let weeks = index.weeks(calendar: calendar)
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].start, calendar.startOfDay(for: date(10, 11)))
        XCTAssertEqual(weeks[1].photos.map(\.date), [date(10, 6), date(10, 4)])
        XCTAssertTrue(index.hasPhoto(inWeekOf: date(10, 9), calendar: calendar))
        XCTAssertFalse(index.hasPhoto(inWeekOf: date(10, 19), calendar: calendar))
    }

    func testWeightChange() {
        let a = ProgressPhotoEntry(date: date(10, 4), weightLbs: 214)
        let b = ProgressPhotoEntry(date: date(10, 18), weightLbs: 208.5)
        XCTAssertEqual(ProgressPhotoIndex.weightChange(from: a, to: b), -5.5)
        XCTAssertNil(ProgressPhotoIndex.weightChange(from: a, to: ProgressPhotoEntry(date: date(10, 19))))
    }

    func testJSONRoundTripAndBadData() throws {
        let index = ProgressPhotoIndex(entries: [
            ProgressPhotoEntry(date: date(10, 4), weightLbs: 214, note: "first"),
            ProgressPhotoEntry(date: date(10, 11))
        ])
        let decoded = ProgressPhotoIndex.decode(try index.encoded())
        XCTAssertEqual(decoded, index)
        XCTAssertEqual(decoded.entries.first?.fileName, index.entries.first?.fileName)
        XCTAssertTrue(ProgressPhotoIndex.decode(Data("nope".utf8)).entries.isEmpty)
    }
}
