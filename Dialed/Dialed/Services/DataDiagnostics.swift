//
//  DataDiagnostics.swift
//  Dialed
//
//  "Is my real data actually arriving?" Home records, for each metric,
//  the value it found and which device/app it came from. The Devices
//  screen shows it as a Data check list so a missing permission or a
//  stalled sync is obvious instead of silently showing "--".
//

import Foundation
#if canImport(Combine)
import Combine
#endif

struct DataSourceStatus: Identifiable, Equatable {
    var id: String { metric }
    let metric: String
    let value: String?
    let source: String?
    let date: Date?

    var isFound: Bool { value != nil }
}

@MainActor
final class DataDiagnostics: ObservableObject {
    static let shared = DataDiagnostics()

    @Published private(set) var rows: [DataSourceStatus] = []
    @Published private(set) var checkedAt: Date?
    @Published var fitbitError: String?

    private init() {}

    func update(rows: [DataSourceStatus]) {
        self.rows = rows
        checkedAt = Date()
    }
}
