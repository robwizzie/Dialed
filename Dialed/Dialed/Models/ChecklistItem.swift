//
//  ChecklistItem.swift
//  Dialed
//
//  Individual checklist task
//

import Foundation
import SwiftData

@Model
final class ChecklistItem {
    var id: UUID
    var dayDate: Date
    var type: String  // ChecklistType rawValue
    var scheduledHour: Int
    var scheduledMinute: Int
    var status: String  // ChecklistStatus rawValue
    var completedAt: Date?
    var skippedAt: Date?

    // Custom task fields
    var customTitle: String?
    var customDescription: String?
    var customPoints: Int?
    var isCustomTask: Bool = false

    init(type: Constants.ChecklistType, dayDate: Date) {
        self.id = UUID()
        self.dayDate = dayDate
        self.type = type.rawValue
        let defaultTime = type.defaultTime
        self.scheduledHour = defaultTime.hour ?? 12
        self.scheduledMinute = defaultTime.minute ?? 0
        self.status = ChecklistStatus.open.rawValue
        self.isCustomTask = false
    }

    // Custom task initializer
    init(customTitle: String, customDescription: String? = nil, customPoints: Int = 1, scheduledTime: DateComponents, dayDate: Date) {
        self.id = UUID()
        self.dayDate = dayDate
        self.type = "custom"
        self.scheduledHour = scheduledTime.hour ?? 12
        self.scheduledMinute = scheduledTime.minute ?? 0
        self.status = ChecklistStatus.open.rawValue
        self.isCustomTask = true
        self.customTitle = customTitle
        self.customDescription = customDescription
        self.customPoints = customPoints
    }

    var checklistType: Constants.ChecklistType? {
        Constants.ChecklistType(rawValue: type)
    }

    var checklistStatus: ChecklistStatus {
        get { ChecklistStatus(rawValue: status) ?? .open }
        set { status = newValue.rawValue }
    }
    
    var scheduledTime: DateComponents {
        DateComponents(hour: scheduledHour, minute: scheduledMinute)
    }

    // Display properties
    var displayTitle: String {
        if isCustomTask {
            return customTitle ?? "Custom Task"
        } else {
            return checklistType?.rawValue ?? "Unknown"
        }
    }

    var displayDescription: String? {
        if isCustomTask {
            return customDescription
        } else {
            return checklistType?.description
        }
    }

    // Note: Points are now calculated dynamically based on total task count
    // Use ChecklistPointsCalculator.points(for:in:) to get actual point value

    func markDone() {
        checklistStatus = .done
        completedAt = Date()
    }

    func markSkipped() {
        checklistStatus = .skipped
        skippedAt = Date()
    }

    func reset() {
        checklistStatus = .open
        completedAt = nil
        skippedAt = nil
    }
}

enum ChecklistStatus: String, Codable {
    case open
    case done
    case skipped
}
