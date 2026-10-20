//
//  DayLoadKit.swift
//  Dialed
//
//  Small pieces for loading a past day on Home: a timeout so one slow
//  source (a Google page, a HealthKit query that never answers) can't hold
//  the rest of the day hostage, and the key a day's results are cached
//  under. Pure Foundation, tested.
//

import Foundation

enum DayLoadKit {

    /// Runs `operation`, giving up after `seconds`. Unlike a task group,
    /// it doesn't wait for the slow work to wind down: the work is
    /// cancelled and left behind, and the caller gets nil right away.
    static func withTimeout<T>(seconds: Double, _ operation: @escaping () async -> T) async -> T? {
        let gate = OnceGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let work = Task {
                let value = await operation()
                if gate.claim() { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if gate.claim() {
                    work.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// "2026-10-19": one cache slot per calendar day.
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Lets exactly one of several racers through.
    final class OnceGate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = true

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard open else { return false }
            open = false
            return true
        }
    }
}
