//
//  RoutineTaskTemplate.swift
//  Dialed
//
//  Template for custom daily routine tasks
//

import Foundation

struct RoutineTaskTemplate: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String?
    var points: Int
    var scheduledTime: DateComponents

    init(title: String, description: String? = nil, points: Int = 1, scheduledTime: DateComponents) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.points = points
        self.scheduledTime = scheduledTime
    }
}
