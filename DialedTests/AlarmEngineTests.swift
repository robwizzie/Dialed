//
//  AlarmEngineTests.swift
//  DialedTests
//
//  The wake-up alarm: when it rings (schedule + one-day changes), when a
//  missed alarm still needs its mission, the re-ring rules, and mission
//  content that's fair and repeatable.
//

import XCTest
@testable import Dialed

final class AlarmEngineTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    private func key(_ d: Date) -> String { WakeAlarmPlan.key(d, calendar: calendar) }

    private var schedule: WakeSchedule {
        var s = WakeSchedule.standard
        s.setDay(nil, on: at(22, 0), calendar: calendar)   // Thursday: sleep in
        s.setDay(270, on: at(23, 0), calendar: calendar)   // Friday: early flight
        return s
    }

    func testFireDatesFollowTheScheduleAndChanges() {
        let dates = WakeAlarmPlan.fireDates(schedule: schedule, extra: [at(20, 21, 10)], from: at(20, 21),
                                            days: 4, calendar: calendar)
        XCTAssertEqual(dates.map(key), ["2026-10-20T21:10", "2026-10-21T06:30", "2026-10-23T04:30", "2026-10-24T08:00"])
    }

    func testDueUntilTheMissionIsDone() {
        let armed = [at(21, 6, 30)]
        XCTAssertEqual(WakeAlarmPlan.due(armed: armed, completed: [], now: at(21, 6, 40), calendar: calendar).map(key),
                       "2026-10-21T06:30")
        XCTAssertNil(WakeAlarmPlan.due(armed: armed, completed: ["2026-10-21T06:30"], now: at(21, 6, 40), calendar: calendar))
        XCTAssertNil(WakeAlarmPlan.due(armed: armed, completed: [], now: at(21, 8), calendar: calendar))
        XCTAssertNil(WakeAlarmPlan.due(armed: armed, completed: [], snoozedUntil: at(21, 6, 45),
                                       now: at(21, 6, 40), calendar: calendar))
        // A long run of snoozes keeps it due an hour past the last one.
        XCTAssertEqual(WakeAlarmPlan.due(armed: armed, completed: [], snoozedUntil: at(21, 7, 50),
                                         now: at(21, 8, 10), calendar: calendar).map(key), "2026-10-21T06:30")
    }

    /// Turning alarms on (or moving today's wake-up earlier) never asks for a
    /// mission for a time that passed without an alarm armed for it.
    func testNoMissionForATimeThatNeverRang() {
        XCTAssertNil(WakeAlarmPlan.due(armed: [], completed: [], now: at(21, 6, 40), calendar: calendar))
        XCTAssertNil(WakeAlarmPlan.due(armed: [at(22, 6, 30)], completed: [], now: at(21, 6, 40), calendar: calendar))
    }

    func testReRingRules() {
        let now = at(21, 6, 31)
        XCTAssertEqual(WakeAlarmPlan.reRing(after: .missionStarted, now: now).timeIntervalSince(now), 90)
        XCTAssertEqual(WakeAlarmPlan.reRing(after: .leftApp, now: now).timeIntervalSince(now), 8)
        XCTAssertEqual(WakeAlarmPlan.reRing(after: .stoppedWithoutMission, now: now).timeIntervalSince(now), 30)
        XCTAssertFalse(WakeAlarmPlan.shouldExtend(lastArmed: now, now: now.addingTimeInterval(10)))
        XCTAssertTrue(WakeAlarmPlan.shouldExtend(lastArmed: now, now: now.addingTimeInterval(25)))
    }

    func testMissionContent() {
        let hard = MissionContent.mathProblems(.hard, seed: 42)
        XCTAssertEqual(hard.count, 4)
        XCTAssertEqual(hard, MissionContent.mathProblems(.hard, seed: 42))
        for p in hard {
            let parts = p.text.split(separator: " ").compactMap { Int($0) }
            XCTAssertEqual(parts[0] * parts[1] + parts[2], p.answer)
        }
        XCTAssertEqual(MissionContent.mathProblems(.easy, seed: 7).count, 2)
        XCTAssertEqual(MissionContent.memoryPattern(side: 3, count: 4, seed: 9).count, 4)
        XCTAssertTrue(MissionContent.phrase(friend: "Dave", difficulty: .easy, seed: 3).contains("Dave"))
        XCTAssertTrue(MissionContent.typedMatches(" i'm beating dave today. ", "I'm beating Dave today."))
        XCTAssertFalse(MissionContent.typedMatches("I'm beating Dave", "I'm beating Dave today."))
    }

    func testPhotoMatchAndFallbackMission() {
        XCTAssertTrue(PhotoMatch.isMatch(distance: 0.6, difficulty: .normal))
        XCTAssertFalse(PhotoMatch.isMatch(distance: 0.6, difficulty: .hard))
        XCTAssertFalse(PhotoMatch.isMatch(distance: .nan, difficulty: .easy))
        var s = WakeAlarmSettings()
        s.mission = .photo
        XCTAssertEqual(s.effectiveMission.single, .math)   // nothing registered yet
        s.hasPhotoReference = true
        XCTAssertEqual(s.effectiveMission.single, .photo)
    }

    func testRandomPickIsStableAndRunnable() {
        var s = WakeAlarmSettings()
        s.pickMode = .randomFrom
        s.randomPool = [.memory, .barcode]          // barcode isn't registered
        for seed in 0..<20 { XCTAssertEqual(s.mission(seed: UInt64(seed)), .memory) }
        s.pickMode = .randomAny
        XCTAssertNil(s.effectiveMission.single)
        XCTAssertEqual(s.mission(seed: 99), s.mission(seed: 99))
        XCTAssertFalse(s.missionPool.contains(.photo))
    }

    func testOlderSettingsStillLoad() throws {
        let old = #"{"enabled":true,"mission":"memory","difficulty":"hard","snoozes":1,"snoozeMinutes":9,"wakeCheck":false,"hasPhotoReference":false,"extra":[]}"#
        let s = try JSONDecoder().decode(WakeAlarmSettings.self, from: Data(old.utf8))
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.mission, .memory)
        XCTAssertEqual(s.tuning.memoryDifficulty, .hard)
        XCTAssertEqual(s.tuning.memoryGrid, 4)
        XCTAssertTrue(s.snoozeEnabled)
        XCTAssertEqual(s.snoozes, 1)
        XCTAssertEqual(s.snoozeMinutes, 9)
        XCTAssertEqual(s.sound, .system)
        XCTAssertEqual(s.pickMode, .single)
        let noSnooze = try JSONDecoder().decode(WakeAlarmSettings.self, from: Data(#"{"snoozes":0}"#.utf8))
        XCTAssertFalse(noSnooze.snoozeEnabled)
        let roundTrip = try JSONDecoder().decode(WakeAlarmSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(roundTrip, s)
    }

    func testSnoozeAndHarder() {
        var s = WakeAlarmSettings()
        XCTAssertFalse(s.canSnooze(used: 0))
        s.snoozeEnabled = true
        s.snoozes = 2
        XCTAssertTrue(s.canSnooze(used: 1))
        XCTAssertFalse(s.canSnooze(used: 2))
        s.snoozeUnlimited = true
        XCTAssertTrue(s.canSnooze(used: 50))
        let t = MissionTuning(preset: .easy).harder(by: 2, for: .math)
        XCTAssertEqual(t.mathDifficulty, .hard)
        XCTAssertEqual(t.mathProblems, 4)
        XCTAssertEqual(MissionContent.mathProblems(.normal, count: 7, seed: 1).count, 7)
    }
}
