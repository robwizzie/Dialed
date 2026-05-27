//
//  MotraIntegration.swift
//  Dialed
//
//  Recognizes workouts that came from Motra (formerly Train Fitness) so we
//  can hand the workout-tracking experience over to that app and skip our
//  in-app "log this workout" prompts.
//
//  Motra writes its workouts to Apple HealthKit as HKWorkout records, which
//  HealthKitManager already reads. The piece we add here is *source
//  recognition* — turning the opaque `sourceRevision.source.name` string
//  into a typed decision the UI can branch on.
//
//  Deep-linking back into Motra is best-effort: Motra hasn't published their
//  URL scheme, so we try a list of plausible candidates and fall back to the
//  App Store listing if none resolve. The first scheme that succeeds on the
//  user's device wins.
//

import Foundation
import UIKit

enum MotraIntegration {

    /// `sourceRevision.source.name` strings that identify a Motra-written
    /// HKWorkout. Motra rebranded from "Train Fitness" in 2025; older HK
    /// records may still carry the old name.
    static let sourceNameMatches: [String] = [
        "Motra",
        "Train Fitness"
    ]

    /// App Store URL — last-resort fallback when the deep-link probes all fail
    /// (Motra not installed, or our scheme list is stale).
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/motra-ai-workout-fitness-coach/id1548577496")!

    /// URL schemes Motra *might* respond to. Tried in order; the first one
    /// that resolves wins. Update this list once we verify the real scheme
    /// on-device (LSApplicationQueriesSchemes in Info.plist will need the
    /// confirmed value to make `canOpenURL` probes accurate, though
    /// `UIApplication.open(_:)` works either way).
    static let candidateSchemes: [String] = [
        "motra",
        "trainfitness",
        "ai.motra",
        "ai.trainfitness"
    ]

    // MARK: - Source recognition

    /// True if a HealthKit workout's source name matches Motra (current or
    /// legacy Train Fitness branding).
    static func isMotraWorkout(sourceName: String?) -> Bool {
        guard let name = sourceName, !name.isEmpty else { return false }
        return sourceNameMatches.contains { name.localizedCaseInsensitiveContains($0) }
    }

    /// Coarse classification of where a HealthKit workout came from. Drives
    /// UI: which tile do we render, do we prompt to log details, etc.
    enum Provenance: Equatable {
        case motra
        case appleNative   // Apple Fitness / Apple Watch native workout app
        case dialed        // we wrote it (via the in-app tracker)
        case other(String?)
    }

    static func provenance(sourceName: String?) -> Provenance {
        guard let name = sourceName, !name.isEmpty else { return .other(nil) }
        if isMotraWorkout(sourceName: name) { return .motra }
        if name.localizedCaseInsensitiveContains("Dialed") { return .dialed }
        if name.localizedCaseInsensitiveContains("Apple Watch")
            || name.localizedCaseInsensitiveContains("Fitness") {
            return .appleNative
        }
        return .other(name)
    }

    // MARK: - Deep linking

    /// Open Motra's main screen, trying each candidate scheme in order.
    /// Falls back to the App Store when nothing resolves.
    @MainActor
    static func openMotra() async {
        for scheme in candidateSchemes {
            guard let url = URL(string: "\(scheme)://") else { continue }
            let opened = await UIApplication.shared.open(url, options: [:])
            if opened { return }
        }
        await UIApplication.shared.open(appStoreURL)
    }
}

// MARK: - WorkoutData convenience

extension HealthKitManager.WorkoutData {
    /// True if the workout was logged by Motra (current or "Train Fitness" branding).
    var isFromMotra: Bool {
        MotraIntegration.isMotraWorkout(sourceName: sourceName)
    }

    /// Classified provenance — see `MotraIntegration.Provenance` for the cases.
    var provenance: MotraIntegration.Provenance {
        MotraIntegration.provenance(sourceName: sourceName)
    }
}
