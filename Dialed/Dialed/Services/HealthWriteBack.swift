//
//  HealthWriteBack.swift
//  Dialed
//
//  Mirrors meals and water logged in Dialed into Apple Health, so other
//  apps (and the Health app itself) see the same intake. Each Dialed
//  event becomes one sample per nutrient, tagged with a sync identifier
//  built from the event id: an edit saves a newer sync version that
//  replaces the old sample, and a delete removes every sample carrying
//  that identifier. Reads elsewhere skip samples from our own source
//  (HealthKitManager.samplePredicate), so nothing is counted twice.
//

import Foundation
import HealthKit

@MainActor
enum HealthWriteBack {
    /// UserDefaults switch; on unless the user turns it off.
    nonisolated static let defaultsKey = "health.writeBack"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private static let store = HKHealthStore()

    /// One nutrient of a Dialed event, with the suffix that keeps its sync
    /// identifier unique next to the event's other nutrients.
    private struct Part {
        let identifier: HKQuantityTypeIdentifier
        let suffix: String
        let unit: HKUnit
        let amount: Double?
    }

    private static func parts(of event: ContextEvent) -> [Part] {
        switch event.kind {
        case .water:
            return [Part(identifier: .dietaryWater, suffix: "water", unit: .fluidOunceUS(), amount: event.value)]
        case .meal:
            return [
                Part(identifier: .dietaryEnergyConsumed, suffix: "energy", unit: .kilocalorie(), amount: event.value),
                Part(identifier: .dietaryProtein, suffix: "protein", unit: .gram(), amount: event.secondaryValue),
                Part(identifier: .dietaryCarbohydrates, suffix: "carbs", unit: .gram(), amount: event.mealCarbs),
                Part(identifier: .dietaryFatTotal, suffix: "fat", unit: .gram(), amount: event.mealFat)
            ]
        default:
            return []
        }
    }

    private static let allSuffixes: [(HKQuantityTypeIdentifier, String)] = [
        (.dietaryWater, "water"),
        (.dietaryEnergyConsumed, "energy"),
        (.dietaryProtein, "protein"),
        (.dietaryCarbohydrates, "carbs"),
        (.dietaryFatTotal, "fat")
    ]

    static func syncIdentifier(eventID: UUID, suffix: String) -> String {
        "dialed-\(eventID.uuidString)-\(suffix)"
    }

    // MARK: - Public API

    /// Write (or rewrite after an edit) a meal or water event. Nutrients
    /// that went to zero / empty are removed from Health.
    static func sync(_ event: ContextEvent) {
        guard isEnabled, HKHealthStore.isHealthDataAvailable() else { return }
        let nutrients = Self.parts(of: event)
        guard !nutrients.isEmpty else { return }

        let id = event.id
        let time = event.timestamp
        // Millisecond timestamp: always grows when `updatedAt` moves forward.
        let version = NSNumber(value: Int64(event.updatedAt.timeIntervalSince1970 * 1000))
        let foodName = event.kind == .meal ? event.mealName : nil

        var samples: [HKObject] = []
        var stale: [(HKQuantityTypeIdentifier, String)] = []
        for part in nutrients {
            guard let type = HKQuantityType.quantityType(forIdentifier: part.identifier),
                  store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            guard let amount = part.amount, amount > 0 else {
                stale.append((part.identifier, part.suffix))
                continue
            }
            var metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: syncIdentifier(eventID: id, suffix: part.suffix),
                HKMetadataKeySyncVersion: version
            ]
            if let foodName { metadata[HKMetadataKeyFoodType] = foodName }
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: part.unit, doubleValue: amount),
                start: time,
                end: time,
                metadata: metadata
            ))
        }

        if !samples.isEmpty {
            store.save(samples) { _, error in
                if let error { print("⚠️ [HealthWriteBack] save failed: \(error.localizedDescription)") }
            }
        }
        for (identifier, suffix) in stale {
            deleteSamples(identifier, syncIdentifier: syncIdentifier(eventID: id, suffix: suffix))
        }
    }

    /// Remove whatever Dialed wrote for an event. Capture the id before the
    /// SwiftData row is deleted.
    static func remove(eventID: UUID) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        for (identifier, suffix) in allSuffixes {
            deleteSamples(identifier, syncIdentifier: syncIdentifier(eventID: eventID, suffix: suffix))
        }
    }

    static func remove(_ event: ContextEvent) {
        guard event.kind == .meal || event.kind == .water else { return }
        remove(eventID: event.id)
    }

    /// Ask for write access when it hasn't been asked yet (shows the Health
    /// sheet only in that case).
    static func requestAccessIfNeeded() async {
        guard isEnabled else { return }
        if await HealthKitManager.shared.needsAuthorizationPrompt() {
            try? await HealthKitManager.shared.requestAuthorization()
        }
    }

    // MARK: - Helpers

    private static func deleteSamples(_ identifier: HKQuantityTypeIdentifier, syncIdentifier: String) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
              store.authorizationStatus(for: type) == .sharingAuthorized else { return }
        let bySync = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                 allowedValues: [syncIdentifier])
        let ours = HKQuery.predicateForObjects(from: [HKSource.default()])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [bySync, ours])
        store.deleteObjects(of: type, predicate: predicate) { _, _, error in
            if let error { print("⚠️ [HealthWriteBack] delete failed: \(error.localizedDescription)") }
        }
    }
}
