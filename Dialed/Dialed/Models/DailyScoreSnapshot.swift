//
//  DailyScoreSnapshot.swift
//  Dialed
//
//  Persisted end-of-day score for each pillar. Lets the Trends view load
//  instantly off SwiftData instead of re-running StateEngine for every
//  day in the window on every render.
//
//  Snapshots are written by DailyScoreSnapshotter:
//    - today's snapshot every time NowViewModel.refresh runs (overwrites
//      in place — the score is "today's, as of now")
//    - yesterday's snapshot every time PlanGenerator regenerates the
//      plan (by then the prior day is final)
//
//  Snapshots are unique per logicalDate — repeat writes upsert.
//

import Foundation
import SwiftData

@Model
final class DailyScoreSnapshot {
    @Attribute(.unique) var id: UUID

    /// Start-of-day for the day this snapshot describes (4 AM cutoff
    /// already applied — matches ContextEvent.logicalDate).
    @Attribute(.unique) var logicalDate: Date

    // Pillar scores 0–100. nil means "we tried to compute but there
    // wasn't enough data" — the chart should break visually rather
    // than render a fake number.
    var recoveryScore: Int?
    var readinessScore: Int?
    var energyScore: Int?
    var strainScore: Int?

    // Confidence 0–1 alongside each score for future "low confidence"
    // dimming in the UI.
    var recoveryConfidence: Double?
    var readinessConfidence: Double?
    var energyConfidence: Double?
    var strainConfidence: Double?

    /// When this row was last computed. Used to skip recomputation when
    /// the underlying samples haven't changed.
    var computedAt: Date

    init(
        logicalDate: Date,
        recoveryScore: Int? = nil,
        readinessScore: Int? = nil,
        energyScore: Int? = nil,
        strainScore: Int? = nil,
        recoveryConfidence: Double? = nil,
        readinessConfidence: Double? = nil,
        energyConfidence: Double? = nil,
        strainConfidence: Double? = nil
    ) {
        self.id = UUID()
        self.logicalDate = logicalDate
        self.recoveryScore = recoveryScore
        self.readinessScore = readinessScore
        self.energyScore = energyScore
        self.strainScore = strainScore
        self.recoveryConfidence = recoveryConfidence
        self.readinessConfidence = readinessConfidence
        self.energyConfidence = energyConfidence
        self.strainConfidence = strainConfidence
        self.computedAt = Date()
    }
}
