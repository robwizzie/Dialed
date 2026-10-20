//
//  AppDirectoryTests.swift
//  DialedTests
//
//  Everything in Dialed is listed once, grouped in order, and findable by
//  the words people actually type.
//

import XCTest
@testable import Dialed

final class AppDirectoryTests: XCTestCase {

    func testEverythingListedOnceInGroupOrder() {
        let all = AppDirectory.search("")
        XCTAssertEqual(all.map(\.group), AppDirectory.Group.allCases)
        XCTAssertEqual(all.reduce(0) { $0 + $1.entries.count }, AppDirectory.all.count)
        XCTAssertEqual(Set(AppDirectory.all.map(\.id)).count, AppDirectory.all.count)
    }

    func testSearchByTitleKeywordAndCase() {
        XCTAssertEqual(AppDirectory.search("weight").first?.entries.first?.target, .trendWeight)
        XCTAssertEqual(AppDirectory.search("BMR").flatMap(\.entries).map(\.target), [.metabolism])
        XCTAssertEqual(AppDirectory.search("log food").flatMap(\.entries).first?.target, .foodLog)
        XCTAssertTrue(AppDirectory.search("alarm").flatMap(\.entries).contains { $0.target == .wakeUp })
        XCTAssertEqual(AppDirectory.search("  Dave ").flatMap(\.entries).map(\.target), [.challenge])
        XCTAssertTrue(AppDirectory.search("zzzz").isEmpty)
    }
}
