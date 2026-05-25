//
//  PillarTrendsViewModel.swift
//  Dialed
//
//  Reads persisted per-pillar scores from DailyScoreSnapshot and surfaces
//  the series + summary stats (avg, min, max, trend) to the Trends view.
//  Snapshot creation lives in DailyScoreSnapshotter; this view model only
//  triggers a one-shot backfill on first read and then queries the table.
//
//  Limitations inherited from the snapshotter:
//    - Energy is a proxy (avg self-reported mood/energy scaled 1–5 → 0–100),
//      not StateEngine.energy — that's a "right now" score that can't be
//      back-fitted to a historical day.
//    - Readiness uses a 1.0 adherence placeholder until the adherence
//      tracker lands; recentStrain reads from the prior day's snapshot.
//

import Foundation
import SwiftData

@MainActor
final class PillarTrendsViewModel: ObservableObject {

    enum Pillar: String, CaseIterable, Identifiable {
        case recovery, readiness, energy, strain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recovery:  return "Recovery"
            case .readiness: return "Readiness"
            case .energy:    return "Energy"
            case .strain:    return "Strain"
            }
        }
    }

    enum Window: String, CaseIterable, Identifiable {
        case week = "7D"
        case twoWeeks = "14D"
        case month = "30D"

        var id: String { rawValue }
        var days: Int {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 30
            }
        }
    }

    struct DailyPoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let score: Int?
    }

    struct Summary: Equatable {
        let average: Int?
        let min: Int?
        let max: Int?
        /// Slope in points/day across the window. Positive = improving for
        /// pillars where higher is better (recovery/readiness/energy);
        /// strain is just descriptive (higher = more loaded).
        let trendPerDay: Double?
    }

    @Published var window: Window = .week
    @Published var selectedPillar: Pillar = .recovery
    @Published private(set) var series: [Pillar: [DailyPoint]] = [:]

    // MARK: - Loading

    func load(context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<window.days).compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }.reversed().map { $0 }  // oldest → newest

        // Backfill any missing snapshots once before reading. Idempotent —
        // existing rows are skipped. Keeps the chart honest after a fresh
        // install or a long absence from the app.
        DailyScoreSnapshotter.backfill(days: window.days, context: context)

        let snapshots = DailyScoreSnapshotter.fetch(
            from: days.first ?? today,
            to: days.last ?? today,
            context: context
        )
        let byDate = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.logicalDate, $0) })

        var recovery: [DailyPoint] = []
        var readiness: [DailyPoint] = []
        var energy: [DailyPoint] = []
        var strain: [DailyPoint] = []

        for day in days {
            let snap = byDate[day]
            recovery.append(.init(date: day, score: snap?.recoveryScore))
            readiness.append(.init(date: day, score: snap?.readinessScore))
            energy.append(.init(date: day, score: snap?.energyScore))
            strain.append(.init(date: day, score: snap?.strainScore))
        }

        series = [
            .recovery: recovery,
            .readiness: readiness,
            .energy: energy,
            .strain: strain
        ]
    }

    // MARK: - Summary

    /// Aggregate stats for the chart card.
    func summary(for pillar: Pillar) -> Summary {
        let points = (series[pillar] ?? []).compactMap { p -> (Date, Int)? in
            guard let s = p.score else { return nil }
            return (p.date, s)
        }
        guard !points.isEmpty else {
            return Summary(average: nil, min: nil, max: nil, trendPerDay: nil)
        }
        let scores = points.map { $0.1 }
        let avg = Int(Double(scores.reduce(0, +)) / Double(scores.count))
        let minS = scores.min()
        let maxS = scores.max()
        return Summary(
            average: avg,
            min: minS,
            max: maxS,
            trendPerDay: trendSlope(points)
        )
    }

    // MARK: - Helpers

    /// Naive least-squares slope in points/day. Returns nil when fewer
    /// than two scored points are available.
    private func trendSlope(_ points: [(Date, Int)]) -> Double? {
        guard points.count >= 2 else { return nil }
        let xs = points.indices.map { Double($0) }
        let ys = points.map { Double($0.1) }
        let n = Double(points.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denom = (n * sumX2 - sumX * sumX)
        guard denom != 0 else { return nil }
        return (n * sumXY - sumX * sumY) / denom
    }
}
