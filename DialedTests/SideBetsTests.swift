//
//  SideBetsTests.swift
//  DialedTests
//
//  Weekly side bets: who leads (fewest skipped days is lower-wins), when a
//  week settles, who owes what, the ledger, the server mapping, and what
//  gets announced.
//

import XCTest
@testable import Dialed

final class SideBetsTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func day(_ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    private func bet(_ metric: SideBets.Metric = .steps, you: Double? = 60_000, friend: Double? = 52_000,
                     status: SideBets.Status = .active, stake: String = "Loser buys wings 🍗") -> SideBets.Bet {
        SideBets.Bet(id: "b1", week: "2026-10-19", metric: metric, stake: stake, proposer: .you, status: status,
                     youScore: you, friendScore: friend)
    }

    func testWeeksRunMondayToSunday() {
        XCTAssertEqual(SideBets.weekKey(day(22), calendar: calendar), "2026-10-19")   // Thursday
        XCTAssertEqual(SideBets.weekKey(day(25), calendar: calendar), "2026-10-19")   // Sunday
        XCTAssertEqual(SideBets.weekKey(day(26), calendar: calendar), "2026-10-26")   // Monday
        XCTAssertEqual(SideBets.daysLeft(bet(), now: day(22), calendar: calendar), 4)
        XCTAssertFalse(SideBets.isOver(bet(), now: day(25, hour: 23), calendar: calendar))
        XCTAssertTrue(SideBets.isOver(bet(), now: day(26, hour: 0), calendar: calendar))
    }

    func testLeaderAndWinner() {
        XCTAssertEqual(SideBets.leader(.steps, you: 10, friend: 8), .you)
        XCTAssertEqual(SideBets.leader(.skippedDays, you: 1, friend: 2), .you)       // fewer is better
        XCTAssertEqual(SideBets.leader(.workouts, you: 3, friend: 3), .tie)
        XCTAssertNil(SideBets.leader(.steps, you: 10, friend: nil))

        XCTAssertNil(SideBets.winner(bet(), now: day(24), calendar: calendar))        // week not over
        XCTAssertEqual(SideBets.winner(bet(), now: day(27), calendar: calendar), .you)
        XCTAssertNil(SideBets.winner(bet(status: .proposed), now: day(27), calendar: calendar))
        XCTAssertNil(SideBets.winner(bet(friend: nil), now: day(27), calendar: calendar))   // waiting on their number
    }

    func testWhoOwesWhat() {
        XCTAssertEqual(SideBets.owes(bet(), winner: .you, friendName: "Dave"), "Dave buys wings 🍗")
        XCTAssertEqual(SideBets.owes(bet(), winner: .friend, friendName: "Dave"), "You buy wings 🍗")
        XCTAssertEqual(SideBets.owes(bet(stake: "Loser does 50 burpees"), winner: .friend, friendName: "Dave"), "You do 50 burpees")
        XCTAssertEqual(SideBets.owes(bet(stake: "Dinner at Chili's"), winner: .you, friendName: "Dave"), "Dave owes you: Dinner at Chili's")
        XCTAssertNil(SideBets.owes(bet(), winner: .tie, friendName: "Dave"))
    }

    func testLedger() {
        let won = bet()
        var lost = bet(you: 2, friend: 5); lost.id = "b2"; lost.week = "2026-10-12"
        var paid = bet(); paid.id = "b3"; paid.week = "2026-10-05"; paid.paid = true
        var tie = bet(you: 3, friend: 3); tie.id = "b4"; tie.week = "2026-09-28"
        let l = SideBets.ledger([won, lost, paid, tie], now: day(27), calendar: calendar)
        XCTAssertEqual([l.wins, l.losses, l.ties], [2, 1, 1])
        XCTAssertEqual(l.unpaid.map(\.id), ["b1", "b2"])
    }

    func testServerMappingFlipsForTheFriend() {
        let w = SideBets.Wire(id: "x", week: "2026-10-19", metric: "miles", stake: "Loser buys wings",
                              proposer: "owner", status: "active", ownerScore: 6.2, friendScore: 4.1, paid: 1, createdAt: nil)
        let owner = SideBets.bet(from: w, role: "owner")!
        XCTAssertEqual(owner.proposer, .you)
        XCTAssertEqual(owner.youScore, 6.2)
        XCTAssertTrue(owner.paid)
        let friend = SideBets.bet(from: w, role: "friend")!
        XCTAssertEqual(friend.proposer, .friend)
        XCTAssertEqual(friend.youScore, 4.1)
        let unknown = SideBets.Wire(id: "y", week: "2026-10-19", metric: "karaoke", stake: "", proposer: "owner",
                                    status: "active", ownerScore: nil, friendScore: nil, paid: nil, createdAt: nil)
        XCTAssertNil(SideBets.bet(from: unknown, role: "owner"))
    }

    func testEvents() {
        var proposedByFriend = bet(status: .proposed)
        proposedByFriend.proposer = .friend
        XCTAssertEqual(SideBets.events(old: [], new: [proposedByFriend], announced: [], now: day(22), calendar: calendar),
                       [.proposed(proposedByFriend)])

        let mine = bet(status: .proposed)
        let accepted = bet()
        XCTAssertEqual(SideBets.events(old: [mine], new: [accepted], announced: [], now: day(22), calendar: calendar),
                       [.accepted(accepted)])

        XCTAssertEqual(SideBets.events(old: [accepted], new: [accepted], announced: [], now: day(27), calendar: calendar),
                       [.settled(accepted, .you)])
        XCTAssertTrue(SideBets.events(old: [accepted], new: [accepted], announced: ["b1"], now: day(27), calendar: calendar).isEmpty)

        let alert = SideBets.alert(.settled(accepted, .you), friendName: "Dave")
        XCTAssertEqual(alert.title, "You won the side bet 🏆")
        XCTAssertTrue(alert.body.contains("Dave buys wings"))
    }
}
