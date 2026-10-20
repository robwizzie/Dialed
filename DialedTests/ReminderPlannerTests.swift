//
//  ReminderPlannerTests.swift
//  DialedTests
//
//  Smart reminders only fire for checkpoints you'd miss, respect quiet
//  hours and the daily cap, and the Sunday review lands on Sunday 6 PM.
//

import XCTest
@testable import Dialed

final class ReminderPlannerTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// Monday, Oct 19 2026 at the given time.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var on: ReminderSettings {
        var s = ReminderSettings()
        s.enabled = true
        return s
    }

    private func inputs(_ now: Date) -> ReminderPlanner.Inputs {
        var i = ReminderPlanner.Inputs(now: now)
        i.waterTargetOz = 120
        i.proteinTarget = 190
        i.calorieTarget = 2_200
        i.stepGoal = 10_000
        return i
    }

    /// Everything you'd need for the rest of the day — no nudges.
    private func onTrack(_ now: Date) -> ReminderPlanner.Inputs {
        var i = inputs(now)
        i.waterOz = 120
        i.proteinGrams = 190
        i.caloriesIn = 1_800
        i.steps = 10_000
        i.weighedInToday = true
        i.lastMealAt = now
        return i
    }

    func testDisabledPlansNothing() {
        XCTAssertTrue(ReminderPlanner.plan(inputs(at(6)), settings: ReminderSettings(), calendar: calendar).isEmpty)
    }

    func testOnTrackDayPlansNothing() {
        XCTAssertTrue(ReminderPlanner.plan(onTrack(at(6)), settings: on, calendar: calendar).isEmpty)
    }

    func testEmptyMorningIsCappedAndSpaced() {
        let plan = ReminderPlanner.plan(inputs(at(6)), settings: on, calendar: calendar)
        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan.first?.kind, .weighIn)
        XCTAssertEqual(plan.first?.fireDate, at(7, 30))
        for (a, b) in zip(plan, plan.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.fireDate.timeIntervalSince(a.fireDate), ReminderPlanner.minSpacing)
        }
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertTrue(plan.allSatisfy { $0.id.hasPrefix(ReminderPlanner.idPrefix) })
    }

    func testDeliveredCountsAgainstCap() {
        var i = inputs(at(10))
        i.deliveredToday = 3
        XCTAssertEqual(ReminderPlanner.plan(i, settings: on, calendar: calendar).count, 1)
        i.deliveredToday = 4
        XCTAssertTrue(ReminderPlanner.plan(i, settings: on, calendar: calendar).isEmpty)
    }

    func testWaterOnlyForCheckpointsYoudMiss() {
        var settings = on
        settings.disabledKinds = [.protein, .steps, .weighIn]
        var i = onTrack(at(10))
        i.waterOz = 50      // ahead of 11 AM (34 oz), behind 2 PM (60 oz)
        let plan = ReminderPlanner.plan(i, settings: settings, calendar: calendar)
        XCTAssertEqual(plan.map(\.fireDate), [at(14), at(17), at(19, 30)])
        XCTAssertTrue(plan.allSatisfy { $0.kind == .water && $0.route == .water })
        XCTAssertTrue(plan[0].body.contains("50 of 120 oz"))
        XCTAssertTrue(plan[0].body.contains("10 oz"))
    }

    func testCatchingUpCancelsWaterNudges() {
        var settings = on
        settings.disabledKinds = [.protein, .steps, .weighIn]
        var i = onTrack(at(15))
        i.waterOz = 110
        XCTAssertTrue(ReminderPlanner.plan(i, settings: settings, calendar: calendar).isEmpty)
    }

    func testPastCheckpointsAreSkipped() {
        let plan = ReminderPlanner.plan(inputs(at(18, 30)), settings: on, calendar: calendar)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > at(18, 30) })
        XCTAssertEqual(plan.map(\.kind), [.water])
    }

    func testQuietHoursDropReminders() {
        var settings = on
        settings.quietStart = 19 * 60      // 7 PM → 7 AM
        let plan = ReminderPlanner.plan(inputs(at(18, 30)), settings: settings, calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(settings.isQuiet(minuteOfDay: 23 * 60))
        XCTAssertTrue(settings.isQuiet(minuteOfDay: 6 * 60))
        XCTAssertFalse(settings.isQuiet(minuteOfDay: 12 * 60))
    }

    func testWeighInOnlyWhenNotWeighedIn() {
        var settings = on
        settings.disabledKinds = [.water, .protein, .steps]
        var i = onTrack(at(6))
        i.weighedInToday = false
        XCTAssertEqual(ReminderPlanner.plan(i, settings: settings, calendar: calendar).map(\.route), [.weighIn])
        i.weighedInToday = true
        XCTAssertTrue(ReminderPlanner.plan(i, settings: settings, calendar: calendar).isEmpty)
    }

    func testNothingSinceNoonNudge() {
        var settings = on
        settings.disabledKinds = [.water, .steps, .weighIn]
        var i = onTrack(at(14))
        i.proteinGrams = 60
        i.lastMealAt = at(11, 40)
        let plan = ReminderPlanner.plan(i, settings: settings, calendar: calendar)
        let gap = plan.first { $0.fireDate == at(15, 30) }
        XCTAssertNotNil(gap)
        XCTAssertEqual(gap?.title, "Nothing logged since 11:40 AM")
        XCTAssertEqual(gap?.route, .foodLog)

        // Logged at 1 PM → no "since noon" nudge.
        i.lastMealAt = at(13)
        XCTAssertNil(ReminderPlanner.plan(i, settings: settings, calendar: calendar).first { $0.fireDate == at(15, 30) })
    }

    func testStepsNudgeSuggestsAWalk() {
        var settings = on
        settings.disabledKinds = [.water, .protein, .weighIn]
        var i = onTrack(at(16))
        i.steps = 4_000
        let plan = ReminderPlanner.plan(i, settings: settings, calendar: calendar)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireDate, at(18))
        XCTAssertTrue(plan.first?.title.contains("walk") ?? false)
        XCTAssertTrue(plan.first?.body.contains("55-min") ?? false)   // 6,000 short ÷ 110 ≈ 55 min
    }

    func testPaceMatchesAvatarMood() {
        XCTAssertEqual(ReminderPlanner.pace(at: at(7), calendar: calendar), 0)
        XCTAssertEqual(ReminderPlanner.pace(at: at(14), calendar: calendar), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ReminderPlanner.pace(at: at(22), calendar: calendar), 1)
    }

    func testWeeklyReviewIsNextSundayAtSix() {
        let monday = at(9)
        let r = ReminderPlanner.weeklyReview(now: monday, settings: on, calendar: calendar)
        XCTAssertEqual(r?.fireDate, at(18, day: 25))
        XCTAssertEqual(r?.route, .weeklyReview)

        // Sunday afternoon → today; Sunday night → next week.
        XCTAssertEqual(ReminderPlanner.weeklyReview(now: at(15, day: 25), settings: on, calendar: calendar)?.fireDate, at(18, day: 25))
        XCTAssertEqual(ReminderPlanner.weeklyReview(now: at(19, day: 25), settings: on, calendar: calendar)?.fireDate,
                       calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18)))

        var off = on
        off.disabledKinds = [.weeklyReview]
        XCTAssertNil(ReminderPlanner.weeklyReview(now: monday, settings: off, calendar: calendar))
    }

    func testTomorrowWeighIn() {
        let r = ReminderPlanner.tomorrowWeighIn(now: at(20), settings: on, calendar: calendar)
        XCTAssertEqual(r?.fireDate, at(7, 30, day: 20))
        XCTAssertEqual(r?.id, "smart.weighIn.2026-10-20.0730")
    }

    func testSettingsRoundTrip() {
        let defaults = UserDefaults(suiteName: "ReminderPlannerTests")!
        defaults.removeObject(forKey: ReminderSettings.storageKey)
        XCTAssertEqual(ReminderSettings.load(from: defaults), ReminderSettings())
        var s = on
        s.disabledKinds = [.steps]
        s.quietStart = 22 * 60
        s.save(to: defaults)
        XCTAssertEqual(ReminderSettings.load(from: defaults), s)
    }
}
