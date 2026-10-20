//
//  HomeLayoutTests.swift
//  DialedTests
//
//  Home card order survives updates: unknown names drop, new cards land in
//  their default spot, moves and hides stick.
//

import XCTest
@testable import Dialed

final class HomeLayoutTests: XCTestCase {

    func testNewCardsSlotInWhereTheyBelong() {
        let saved = HomeSection.allCases.filter { $0 != .race && $0 != .patterns }.map(\.rawValue)
        XCTAssertEqual(HomeLayout(savedOrder: saved, savedHidden: []).order, HomeSection.allCases)
    }

    func testJunkIsIgnored() {
        let l = HomeLayout(savedOrder: ["fuel", "bogus", "fuel"], savedHidden: ["coach", "nope"])
        XCTAssertEqual(l.order.first, .morning)
        XCTAssertEqual(l.order.filter { $0 == .fuel }.count, 1)
        XCTAssertEqual(l.hidden, [.coach])
        XCTAssertEqual(Set(l.order), Set(HomeSection.allCases))
    }

    func testMoveHideAndSave() {
        var l = HomeLayout.standard
        l.move(from: IndexSet([HomeSection.allCases.firstIndex(of: .fuel)!]), to: 0)
        XCTAssertEqual(l.order.first, .fuel)
        l.toggle(.hero)
        XCTAssertFalse(l.visible.contains(.hero))
        let defaults = UserDefaults(suiteName: "HomeLayoutTests")!
        l.save(defaults)
        XCTAssertEqual(HomeLayout.load(defaults), l)
        HomeLayout.reset(defaults)
    }
}
