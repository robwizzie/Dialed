//
//  GoogleHealthDTO.swift
//  Dialed
//
//  Wire types for the Google Health API v4 (from its discovery document).
//  Only the fields Dialed reads are modeled; everything is optional so a
//  missing field never fails a whole response. int64 values arrive as JSON
//  strings, so they decode through `GHInt`. Pure Foundation — unit-tested.
//

import Foundation

/// int64 that may arrive as "123" or 123.
struct GHInt: Decodable, Equatable {
    let value: Int

    init(_ value: Int) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) {
            value = n
        } else if let s = try? c.decode(String.self), let n = Int(s) {
            value = n
        } else if let d = try? c.decode(Double.self) {
            value = Int(d)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected int64")
        }
    }
}

struct GHDate: Codable, Equatable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    func date(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// "YYYY-MM-DD" for filter expressions.
    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

struct GHCivilDateTime: Codable, Equatable {
    var date: GHDate
}

struct GHSampleTime: Decodable {
    let physicalTime: String?
}

struct GHInterval: Decodable {
    let startTime: String?
    let endTime: String?
}

// MARK: - Data points

struct GHDataPoint: Decodable {
    let name: String?
    let weight: Weight?
    let heartRate: HeartRate?
    let dailyRestingHeartRate: DailyRestingHeartRate?
    let dailyHeartRateVariability: DailyHRV?
    let dailyOxygenSaturation: DailyOxygenSaturation?
    let dailyRespiratoryRate: DailyRespiratoryRate?
    let sleep: Sleep?
    let dailySleepTemperatureDerivations: DailySleepTemperature?

    struct Weight: Decodable {
        let weightGrams: Double?
        let sampleTime: GHSampleTime?
    }

    struct HeartRate: Decodable {
        let beatsPerMinute: GHInt?
        let sampleTime: GHSampleTime?
    }

    struct DailyRestingHeartRate: Decodable {
        let date: GHDate?
        let beatsPerMinute: GHInt?
    }

    struct DailyHRV: Decodable {
        let date: GHDate?
        let averageHeartRateVariabilityMilliseconds: Double?
    }

    struct DailyOxygenSaturation: Decodable {
        let date: GHDate?
        let averagePercentage: Double?
    }

    struct DailyRespiratoryRate: Decodable {
        let date: GHDate?
        let breathsPerMinute: Double?
    }

    /// Nightly skin temperature and the 30-day median it's judged against.
    struct DailySleepTemperature: Decodable {
        let date: GHDate?
        let nightlyTemperatureCelsius: Double?
        let baselineTemperatureCelsius: Double?
    }

    struct Sleep: Decodable {
        let interval: GHInterval?
        let summary: Summary?
        let metadata: Metadata?
        /// Contiguous stage segments covering the whole sleep period.
        let stages: [StageSegment]?

        struct StageSegment: Decodable {
            let type: String?
            let startTime: String?
            let endTime: String?
        }

        struct Summary: Decodable {
            let minutesAsleep: GHInt?
            let minutesAwake: GHInt?
            let minutesInSleepPeriod: GHInt?
            let stagesSummary: [Stage]?
        }

        struct Stage: Decodable {
            let type: String?
            let minutes: GHInt?
        }

        struct Metadata: Decodable {
            let mainSleep: Bool?
            let nap: Bool?
            let externalId: String?
        }

        func minutes(of stage: String) -> Int? {
            summary?.stagesSummary?.first(where: { $0.type == stage })?.minutes?.value
        }
    }
}

struct GHListResponse: Decodable {
    let dataPoints: [GHDataPoint]?
    let nextPageToken: String?
}

// MARK: - Daily roll-up

struct GHDailyRollUpRequest: Encodable {
    struct Range: Encodable {
        let start: GHCivilDateTime
        let end: GHCivilDateTime
    }
    let range: Range
    let windowSizeDays: Int
}

struct GHDailyRollUpResponse: Decodable {
    let rollupDataPoints: [Point]?
    let nextPageToken: String?

    struct Point: Decodable {
        let civilStartTime: GHCivilDateTime?
        let steps: Steps?
        let hydrationLog: Hydration?

        struct Steps: Decodable { let countSum: GHInt? }
        struct Hydration: Decodable {
            let amountConsumed: Amount?
            struct Amount: Decodable { let millilitersSum: Double? }
        }
    }
}

// MARK: - Time

enum GHTime {
    /// RFC 3339 with optional fractional seconds of any precision
    /// ("2026-10-18T06:12:30.123456789Z", "...+02:00").
    static func parse(_ string: String?) -> Date? {
        guard var s = string, !s.isEmpty else { return nil }
        if let dot = s.firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            s.removeSubrange(dot..<end)
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// RFC 3339 UTC literal for filter expressions.
    static func rfc3339(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
