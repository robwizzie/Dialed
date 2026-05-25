//
//  PlanGeneratorTests.swift
//  DialedTests
//
//  Pure tests for PlanGenerator's anchor resolution and recovery filter.
//  We don't exercise the SwiftData orchestration here — that path is
//  covered by integration tests in the build (and would require a real
//  ModelContainer fixture).
//

import XCTest
@testable import Dialed

final class PlanGeneratorTests: XCTestCase {

    // MARK: - Anchor resolution

    func testResolveStart_wallClock() {
        let block = makeBlock(anchor: .wallClock, offsetMinutes: 8 * 60 + 30)  // 08:30
        let inputs = makeInputs(
            date: makeDay(),
            wakeHour: 7,
            sleepHour: 23
        )
        let resolved = PlanGenerator.resolveStart(block: block, inputs: inputs)
        XCTAssertEqual(Calendar.current.component(.hour, from: resolved), 8)
        XCTAssertEqual(Calendar.current.component(.minute, from: resolved), 30)
    }

    func testResolveStart_afterWakeSlidesWithWakeTime() {
        let block = makeBlock(anchor: .afterWake, offsetMinutes: 90)  // 1.5h after waking
        // Same template block resolves to *different* wall-clock times for
        // different wake times — that's the whole point of the redesign.
        let early = PlanGenerator.resolveStart(
            block: block,
            inputs: makeInputs(date: makeDay(), wakeHour: 6)
        )
        let late = PlanGenerator.resolveStart(
            block: block,
            inputs: makeInputs(date: makeDay(), wakeHour: 9)
        )
        XCTAssertEqual(Calendar.current.component(.hour, from: early), 7)   // 6 + 1.5
        XCTAssertEqual(Calendar.current.component(.minute, from: early), 30)
        XCTAssertEqual(Calendar.current.component(.hour, from: late), 10)   // 9 + 1.5
        XCTAssertEqual(Calendar.current.component(.minute, from: late), 30)
    }

    func testResolveStart_beforeSleepSubtractsFromSleepTarget() {
        let block = makeBlock(anchor: .beforeSleep, offsetMinutes: 60)
        let inputs = makeInputs(date: makeDay(), wakeHour: 7, sleepHour: 22)
        let resolved = PlanGenerator.resolveStart(block: block, inputs: inputs)
        XCTAssertEqual(Calendar.current.component(.hour, from: resolved), 21)
        XCTAssertEqual(Calendar.current.component(.minute, from: resolved), 0)
    }

    // MARK: - resolveBlocks weekday + recovery filtering

    func testResolveBlocks_filtersByWeekday() {
        let template = WeeklyTemplate(name: "T", isActive: true)
        let mondayOnly = TemplateBlock.WeekdayMask.single(2)  // Mon
        let block = makeBlock(
            anchor: .wallClock, offsetMinutes: 9 * 60,
            weekdayMask: mondayOnly
        )
        block.template = template
        template.blocks = [block]

        let sundayInputs = makeInputs(date: makeDay(weekday: 1), template: template)
        let mondayInputs = makeInputs(date: makeDay(weekday: 2), template: template)

        XCTAssertEqual(PlanGenerator.resolveBlocks(sundayInputs).count, 0)
        XCTAssertEqual(PlanGenerator.resolveBlocks(mondayInputs).count, 1)
    }

    func testResolveBlocks_autoSkipsBelowMinRecovery() {
        let template = WeeklyTemplate(name: "T", isActive: true)
        let hardWorkout = makeBlock(
            anchor: .wallClock, offsetMinutes: 17 * 60 + 30,
            minRecovery: 60
        )
        hardWorkout.template = template
        template.blocks = [hardWorkout]

        let lowRecovery = makeInputs(
            date: makeDay(),
            template: template,
            recoveryScore: 35
        )
        let resolved = PlanGenerator.resolveBlocks(lowRecovery)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertFalse(resolved[0].included)
        XCTAssertNotNil(resolved[0].skipReason)
    }

    func testResolveBlocks_keepsBlocksAtOrAboveMinRecovery() {
        let template = WeeklyTemplate(name: "T", isActive: true)
        let hardWorkout = makeBlock(
            anchor: .wallClock, offsetMinutes: 17 * 60 + 30,
            minRecovery: 60
        )
        hardWorkout.template = template
        template.blocks = [hardWorkout]

        let goodDay = makeInputs(date: makeDay(), template: template, recoveryScore: 75)
        let resolved = PlanGenerator.resolveBlocks(goodDay)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertTrue(resolved[0].included)
    }

    func testResolveBlocks_orderedByStartThenSortOrder() {
        let template = WeeklyTemplate(name: "T", isActive: true)
        // Two blocks at the same time (12:00), different sortOrders
        let later = makeBlock(anchor: .wallClock, offsetMinutes: 12 * 60, sortOrder: 2)
        let earlier = makeBlock(anchor: .wallClock, offsetMinutes: 12 * 60, sortOrder: 1)
        let dawn = makeBlock(anchor: .wallClock, offsetMinutes: 6 * 60, sortOrder: 0)
        [later, earlier, dawn].forEach { $0.template = template }
        template.blocks = [later, earlier, dawn]

        let resolved = PlanGenerator.resolveBlocks(makeInputs(date: makeDay(), template: template))
        XCTAssertEqual(resolved.count, 3)
        XCTAssertEqual(resolved[0].templateBlock.id, dawn.id)
        XCTAssertEqual(resolved[1].templateBlock.id, earlier.id)
        XCTAssertEqual(resolved[2].templateBlock.id, later.id)
    }

    // MARK: - WeekdayMask helpers

    func testWeekdayMask_singleIsolatesADay() {
        let mask = TemplateBlock.WeekdayMask.single(2)  // Mon
        let block = makeBlock(anchor: .wallClock, offsetMinutes: 0, weekdayMask: mask)
        XCTAssertTrue(block.runs(on: 2))
        XCTAssertFalse(block.runs(on: 3))
        XCTAssertFalse(block.runs(on: 1))
    }

    func testWeekdayMask_everyDayIncludesAll() {
        let block = makeBlock(
            anchor: .wallClock, offsetMinutes: 0,
            weekdayMask: TemplateBlock.WeekdayMask.everyDay
        )
        for w in 1...7 {
            XCTAssertTrue(block.runs(on: w))
        }
    }

    func testWeekdayMask_weekdaysExcludesWeekend() {
        let block = makeBlock(
            anchor: .wallClock, offsetMinutes: 0,
            weekdayMask: TemplateBlock.WeekdayMask.weekdays
        )
        XCTAssertFalse(block.runs(on: 1))  // Sunday
        XCTAssertTrue(block.runs(on: 2))
        XCTAssertTrue(block.runs(on: 6))
        XCTAssertFalse(block.runs(on: 7))  // Saturday
    }

    // MARK: - Helpers

    private func makeBlock(
        anchor: TemplateBlock.Anchor,
        offsetMinutes: Int,
        weekdayMask: Int = TemplateBlock.WeekdayMask.everyDay,
        minRecovery: Int? = nil,
        sortOrder: Int = 0
    ) -> TemplateBlock {
        TemplateBlock(
            kind: .routine,
            title: "Test block",
            weekdayMask: weekdayMask,
            anchor: anchor,
            anchorOffsetMinutes: offsetMinutes,
            durationMinutes: 30,
            minRecovery: minRecovery,
            sortOrder: sortOrder
        )
    }

    private func makeInputs(
        date: Date,
        template: WeeklyTemplate = WeeklyTemplate(name: "T"),
        wakeHour: Int = 7,
        sleepHour: Int = 23,
        recoveryScore: Int? = nil
    ) -> PlanGenerator.Inputs {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let wake = calendar.date(bySettingHour: wakeHour, minute: 0, second: 0, of: dayStart)!
        let sleep = calendar.date(bySettingHour: sleepHour, minute: 0, second: 0, of: dayStart)!

        return PlanGenerator.Inputs(
            date: date,
            template: template,
            wakeTime: wake,
            sleepTargetTime: sleep,
            recoveryScore: recoveryScore,
            readinessScore: nil
        )
    }

    /// Pick a date with a specific weekday (1 = Sun, 2 = Mon, ...).
    private func makeDay(weekday: Int = 4) -> Date {
        // 2026-01-12 was a Monday. We shift from there.
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 11  // Sun
        let calendar = Calendar.current
        let sunday = calendar.date(from: comps)!
        return calendar.date(byAdding: .day, value: weekday - 1, to: sunday)!
    }
}
