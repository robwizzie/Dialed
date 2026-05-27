//
//  AppStateWhatsNewTests.swift
//  DialedTests
//
//  Locks in the "show the sheet once per major version" contract.
//

import XCTest
@testable import Dialed

@MainActor
final class AppStateWhatsNewTests: XCTestCase {

    private let keyOnboarding = "hasCompletedOnboarding"
    private let keyWhatsNew = "lastSeenWhatsNewVersion"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: keyOnboarding)
        UserDefaults.standard.removeObject(forKey: keyWhatsNew)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: keyOnboarding)
        UserDefaults.standard.removeObject(forKey: keyWhatsNew)
        super.tearDown()
    }

    // MARK: - Suppression during onboarding

    func testShouldShowWhatsNew_suppressedWhenOnboardingNotComplete() {
        let state = AppState()
        // Default: onboarding incomplete, lastSeen = 0.
        XCTAssertFalse(state.shouldShowWhatsNew,
                       "First-run users should see onboarding, not the What's New sheet")
    }

    // MARK: - Shows once after onboarding

    func testShouldShowWhatsNew_showsAfterOnboardingWhenVersionTrails() {
        let state = AppState()
        state.completeOnboarding()
        // lastSeen stays at 0, current version is 2 → should show.
        XCTAssertTrue(state.shouldShowWhatsNew)
    }

    // MARK: - Dismisses after marking seen

    func testMarkWhatsNewSeen_advancesPersistedVersion() {
        let state = AppState()
        state.completeOnboarding()
        XCTAssertTrue(state.shouldShowWhatsNew)

        state.markWhatsNewSeen()
        XCTAssertEqual(state.lastSeenWhatsNewVersion, WhatsNew.currentVersion)
        XCTAssertFalse(state.shouldShowWhatsNew,
                       "After dismissal, the sheet should not re-present on the same version")
    }

    // MARK: - Persistence across app launches

    func testShouldShowWhatsNew_isPersistedAcrossInstances() {
        let first = AppState()
        first.completeOnboarding()
        first.markWhatsNewSeen()

        // Simulate app re-launch.
        let second = AppState()
        XCTAssertTrue(second.hasCompletedOnboarding)
        XCTAssertEqual(second.lastSeenWhatsNewVersion, WhatsNew.currentVersion)
        XCTAssertFalse(second.shouldShowWhatsNew)
    }

    // MARK: - Re-appears on version bump

    func testShouldShowWhatsNew_reappearsWhenStoredVersionFallsBehind() {
        let state = AppState()
        state.completeOnboarding()
        // Pretend the user last saw version 0 (e.g. coming from before the
        // What's New system existed).
        state.lastSeenWhatsNewVersion = 0
        XCTAssertLessThan(state.lastSeenWhatsNewVersion, WhatsNew.currentVersion)
        XCTAssertTrue(state.shouldShowWhatsNew,
                      "When stored version trails current, the sheet should re-appear")
    }
}
