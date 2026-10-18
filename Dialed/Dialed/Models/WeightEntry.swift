//
//  WeightEntry.swift
//  Dialed
//
//  A manual weigh-in typed into Dialed. Scale readings that arrive through
//  Apple Health or Fitbit are read live and never copied here — this table
//  only holds what the user entered by hand, so it can't double-count.
//

import Foundation
import SwiftData

@Model
final class WeightEntry {
    @Attribute(.unique) var id: UUID

    var timestamp: Date
    var pounds: Double
    var bodyFatPercent: Double?
    var note: String?

    var createdAt: Date

    init(timestamp: Date = Date(), pounds: Double, bodyFatPercent: Double? = nil, note: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.pounds = pounds
        self.bodyFatPercent = bodyFatPercent
        self.note = note
        self.createdAt = Date()
    }
}
