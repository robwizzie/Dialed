//
//  MotraIntegrationTests.swift
//  DialedTests
//
//  Unit tests for the Motra source-recognition heuristics. These run cold —
//  no HealthKit access needed.
//

import XCTest
@testable import Dialed

final class MotraIntegrationTests: XCTestCase {

    // MARK: - isMotraWorkout

    func testIsMotra_matchesCurrentBranding() {
        XCTAssertTrue(MotraIntegration.isMotraWorkout(sourceName: "Motra"))
    }

    func testIsMotra_matchesLegacyTrainFitnessBranding() {
        XCTAssertTrue(MotraIntegration.isMotraWorkout(sourceName: "Train Fitness"))
    }

    func testIsMotra_caseInsensitive() {
        XCTAssertTrue(MotraIntegration.isMotraWorkout(sourceName: "motra"))
        XCTAssertTrue(MotraIntegration.isMotraWorkout(sourceName: "TRAIN FITNESS"))
    }

    func testIsMotra_matchesEmbeddedSubstring() {
        // Some apps append " on iPhone" / " on Apple Watch" to the source name.
        XCTAssertTrue(MotraIntegration.isMotraWorkout(sourceName: "Motra on Apple Watch"))
        XCTAssertTrue(MotraIntegration.isMotraWorkout(sourceName: "Train Fitness — Workouts"))
    }

    func testIsMotra_rejectsUnrelatedSources() {
        XCTAssertFalse(MotraIntegration.isMotraWorkout(sourceName: "Apple Watch"))
        XCTAssertFalse(MotraIntegration.isMotraWorkout(sourceName: "Fitness"))
        XCTAssertFalse(MotraIntegration.isMotraWorkout(sourceName: "Strava"))
        XCTAssertFalse(MotraIntegration.isMotraWorkout(sourceName: "Dialed"))
    }

    func testIsMotra_handlesNilAndEmpty() {
        XCTAssertFalse(MotraIntegration.isMotraWorkout(sourceName: nil))
        XCTAssertFalse(MotraIntegration.isMotraWorkout(sourceName: ""))
    }

    // MARK: - provenance

    func testProvenance_motraTakesPriorityOverFitnessSubstring() {
        // Source string contains both "Motra" and "Fitness". We want .motra,
        // not .appleNative, since the Motra check runs first.
        let p = MotraIntegration.provenance(sourceName: "Motra Fitness")
        XCTAssertEqual(p, .motra)
    }

    func testProvenance_appleNativeForWatchOrFitness() {
        XCTAssertEqual(MotraIntegration.provenance(sourceName: "Apple Watch"), .appleNative)
        XCTAssertEqual(MotraIntegration.provenance(sourceName: "Fitness"), .appleNative)
    }

    func testProvenance_dialedSelfRecognition() {
        XCTAssertEqual(MotraIntegration.provenance(sourceName: "Dialed"), .dialed)
    }

    func testProvenance_otherForUnknown() {
        XCTAssertEqual(MotraIntegration.provenance(sourceName: "Strava"), .other("Strava"))
    }

    func testProvenance_otherForNil() {
        XCTAssertEqual(MotraIntegration.provenance(sourceName: nil), .other(nil))
    }

    // MARK: - candidate schemes

    func testCandidateSchemes_hasMotraFirst() {
        // The current-branding scheme should be tried before the legacy one.
        XCTAssertEqual(MotraIntegration.candidateSchemes.first, "motra")
    }

    func testCandidateSchemes_areAllValidURLComponents() {
        for scheme in MotraIntegration.candidateSchemes {
            XCTAssertNotNil(URL(string: "\(scheme)://"), "Scheme `\(scheme)` does not produce a valid URL")
        }
    }
}
