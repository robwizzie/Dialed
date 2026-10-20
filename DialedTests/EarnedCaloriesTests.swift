//
//  EarnedCaloriesTests.swift
//  DialedTests
//
//  Every workout's burn goes back into the budget, once.
//

import XCTest
@testable import Dialed

final class EarnedCaloriesTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ id: String, _ start: Double, _ end: Double, _ calories: Double,
                       _ source: EarnedCalories.Entry.Source) -> EarnedCalories.Entry {
        .init(id: id, name: id, symbol: "", start: base.addingTimeInterval(start * 60),
              end: base.addingTimeInterval(end * 60), calories: calories, source: source)
    }

    func testWatchBeatsTheSameLoggedSessionAndEverythingElseAdds() {
        let day = EarnedCalories.combine([
            entry("logged lift", 15, 45, 245, .logged),
            entry("watch lift", 14, 46, 210, .watch),
            entry("treadmill run", 0, 15, 130, .logged),
            entry("pickleball", 120, 180, 560, .fun)
        ])
        XCTAssertEqual(day.entries.map(\.id), ["treadmill run", "watch lift", "pickleball"])
        XCTAssertEqual(day.earned, 900)
    }

    func testEstimates() {
        XCTAssertEqual(EarnedCalories.strengthCalories(minutes: 30, weightLbs: 206), 245)
        XCTAssertEqual(EarnedCalories.cardioCalories(kind: "Run", minutes: 15, miles: 1, weightLbs: 206), 130)
        XCTAssertEqual(EarnedCalories.cardioCalories(kind: "Walk", minutes: nil, miles: 2, weightLbs: 200), 120)
    }
}
