//
//  ChecklistPointsCalculator.swift
//  Dialed
//
//  Automatically distributes routine points among checklist tasks
//

import Foundation

struct ChecklistPointsCalculator {
    /// Total points allocated to routine/checklist in daily score
    static let totalRoutinePoints = Constants.Scoring.routineWeight

    /// Calculate points for each checklist item based on total task count
    /// Ensures fair distribution and total equals exactly totalRoutinePoints
    static func calculatePoints(for items: [ChecklistItem]) -> [UUID: Int] {
        // Filter to only tasks that count for points
        let scoredItems = items.filter { item in
            if item.isCustomTask {
                // All custom tasks count for points
                return true
            } else {
                // Check if predefined task counts
                return item.checklistType?.countsForPoints ?? false
            }
        }

        guard !scoredItems.isEmpty else {
            return [:]
        }

        // Calculate base points per task
        let basePoints = totalRoutinePoints / scoredItems.count
        let remainder = totalRoutinePoints % scoredItems.count

        var pointsMap: [UUID: Int] = [:]

        // Distribute points
        for (index, item) in scoredItems.enumerated() {
            // Give base points to all, plus 1 extra point to first 'remainder' tasks
            // This ensures total equals exactly totalRoutinePoints
            let points = basePoints + (index < remainder ? 1 : 0)
            pointsMap[item.id] = points
        }

        return pointsMap
    }

    /// Get points for a specific checklist item
    static func points(for item: ChecklistItem, in items: [ChecklistItem]) -> Int {
        let pointsMap = calculatePoints(for: items)
        return pointsMap[item.id] ?? 0
    }

    /// Calculate total points earned from checklist items
    static func totalPointsEarned(from items: [ChecklistItem]) -> Int {
        let pointsMap = calculatePoints(for: items)

        return items.reduce(0) { total, item in
            guard item.checklistStatus == .done else { return total }
            guard let points = pointsMap[item.id] else { return total }
            return total + points
        }
    }
}
