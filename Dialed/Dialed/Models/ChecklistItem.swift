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
    var scheduledTime: DateComponents
    var status: String  // ChecklistStatus rawValue
    var completedAt: Date?
    var skippedAt: Date?

    init(type: Constants.ChecklistType, dayDate: Date) {
        self.id = UUID()
        self.dayDate = dayDate
        self.type = type.rawValue
        self.scheduledTime = type.defaultTime
        self.status = ChecklistStatus.open.rawValue
    }

    var checklistType: Constants.ChecklistType? {
        Constants.ChecklistType(rawValue: type)
    }

    var checklistStatus: ChecklistStatus {
        get { ChecklistStatus(rawValue: status) ?? .open }
        set { status = newValue.rawValue }
    }

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
