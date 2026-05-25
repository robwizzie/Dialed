//
//  FitbitAPIClient.swift
//  Dialed
//
//  Thin client for the Fitbit Web API. Handles bearer-token injection,
//  silent refresh on 401, JSON decoding to internal DTOs.
//
//  Reference: https://dev.fitbit.com/build/reference/web-api/
//

import Foundation

/// Internal DTOs match Fitbit's wire format. Translation to domain models
/// (SleepSession, BiometricSnapshot) happens in FitbitSyncService.
enum FitbitDTO {

    // MARK: Sleep — /1.2/user/-/sleep/date/[date].json
    struct SleepResponse: Decodable {
        let sleep: [SleepEntry]
        let summary: SleepSummary?

        struct SleepEntry: Decodable {
            let logId: Int64
            let dateOfSleep: String   // "YYYY-MM-DD"
            let startTime: String     // "2026-05-25T22:34:00.000"
            let endTime: String
            let duration: Int         // ms
            let efficiency: Int       // 0–100
            let isMainSleep: Bool
            let minutesAsleep: Int
            let minutesAwake: Int
            let minutesAfterWakeup: Int?
            let minutesToFallAsleep: Int?
            let timeInBed: Int
            let levels: SleepLevels?
        }

        struct SleepLevels: Decodable {
            let summary: SleepLevelSummary?
        }

        struct SleepLevelSummary: Decodable {
            let deep: SleepLevelBucket?
            let rem: SleepLevelBucket?
            let light: SleepLevelBucket?
            let wake: SleepLevelBucket?
            let asleep: SleepLevelBucket?  // legacy short sleeps
            let restless: SleepLevelBucket?
            let awake: SleepLevelBucket?
        }

        struct SleepLevelBucket: Decodable {
            let count: Int?
            let minutes: Int
        }

        struct SleepSummary: Decodable {
            let totalMinutesAsleep: Int?
            let totalSleepRecords: Int?
            let totalTimeInBed: Int?
        }
    }

    // MARK: HRV — /1/user/-/hrv/date/[date].json
    struct HRVResponse: Decodable {
        let hrv: [HRVEntry]
        struct HRVEntry: Decodable {
            let dateTime: String
            let value: HRVValue
        }
        struct HRVValue: Decodable {
            let dailyRmssd: Double?
            let deepRmssd: Double?
        }
    }

    // MARK: Heart rate — /1/user/-/activities/heart/date/[date]/1d.json
    struct HeartRateResponse: Decodable {
        let activitiesHeart: [HeartRateDay]

        enum CodingKeys: String, CodingKey {
            case activitiesHeart = "activities-heart"
        }

        struct HeartRateDay: Decodable {
            let dateTime: String
            let value: HeartRateValue
        }

        struct HeartRateValue: Decodable {
            let restingHeartRate: Int?
            let heartRateZones: [Zone]?
        }

        struct Zone: Decodable {
            let name: String?
            let min: Int?
            let max: Int?
            let minutes: Int?
        }
    }

    // MARK: SpO2 — /1/user/-/spo2/date/[date].json
    struct SpO2Response: Decodable {
        let dateTime: String?
        let value: SpO2Value?
        struct SpO2Value: Decodable {
            let avg: Double?
            let min: Double?
            let max: Double?
        }
    }

    // MARK: Breathing rate — /1/user/-/br/date/[date].json
    struct BreathingRateResponse: Decodable {
        let br: [BREntry]
        struct BREntry: Decodable {
            let dateTime: String
            let value: BRValue
        }
        struct BRValue: Decodable {
            let breathingRate: Double?
        }
    }

    // MARK: Skin temp — /1/user/-/temp/skin/date/[date].json
    struct SkinTempResponse: Decodable {
        let tempSkin: [SkinTempEntry]?
        struct SkinTempEntry: Decodable {
            let dateTime: String
            let value: SkinTempValue
            let logType: String?
        }
        struct SkinTempValue: Decodable {
            /// Δ°C from baseline (Fitbit "nightlyRelative" mode).
            let nightlyRelative: Double?
        }
    }

    // MARK: Activity summary — /1/user/-/activities/date/[date].json
    struct ActivitySummaryResponse: Decodable {
        let summary: ActivitySummary?
        struct ActivitySummary: Decodable {
            let steps: Int?
            let activityCalories: Int?
            let caloriesOut: Int?
        }
    }
}

@MainActor
final class FitbitAPIClient {
    static let shared = FitbitAPIClient()

    private let auth = FitbitAuthService.shared
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    enum APIError: LocalizedError {
        case notConnected
        case httpStatus(Int, String)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to Fitbit."
            case .httpStatus(let code, let body): return "Fitbit HTTP \(code): \(body)"
            case .decodingFailed(let detail): return "Decoding failed: \(detail)"
            }
        }
    }

    // MARK: - Endpoint helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    func sleep(on date: Date) async throws -> FitbitDTO.SleepResponse {
        let path = "/1.2/user/-/sleep/date/\(Self.dateFormatter.string(from: date)).json"
        return try await request(path: path)
    }

    func hrv(on date: Date) async throws -> FitbitDTO.HRVResponse {
        let path = "/1/user/-/hrv/date/\(Self.dateFormatter.string(from: date)).json"
        return try await request(path: path)
    }

    func heartRate(on date: Date) async throws -> FitbitDTO.HeartRateResponse {
        let path = "/1/user/-/activities/heart/date/\(Self.dateFormatter.string(from: date))/1d.json"
        return try await request(path: path)
    }

    func spO2(on date: Date) async throws -> FitbitDTO.SpO2Response {
        let path = "/1/user/-/spo2/date/\(Self.dateFormatter.string(from: date)).json"
        return try await request(path: path)
    }

    func breathingRate(on date: Date) async throws -> FitbitDTO.BreathingRateResponse {
        let path = "/1/user/-/br/date/\(Self.dateFormatter.string(from: date)).json"
        return try await request(path: path)
    }

    func skinTemperature(on date: Date) async throws -> FitbitDTO.SkinTempResponse {
        let path = "/1/user/-/temp/skin/date/\(Self.dateFormatter.string(from: date)).json"
        return try await request(path: path)
    }

    func activitySummary(on date: Date) async throws -> FitbitDTO.ActivitySummaryResponse {
        let path = "/1/user/-/activities/date/\(Self.dateFormatter.string(from: date)).json"
        return try await request(path: path)
    }

    // MARK: - Core request

    private func request<T: Decodable>(path: String) async throws -> T {
        let token = try await auth.validAccessToken()
        let url = FitbitConfig.apiBaseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        let http = response as? HTTPURLResponse
        switch http?.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                let body = String(data: data, encoding: .utf8) ?? "<binary>"
                throw APIError.decodingFailed("\(error.localizedDescription) — body: \(body.prefix(500))")
            }
        case 401:
            // Token expired between our refresh check and the request — force a refresh
            // and try once more.
            _ = try await auth.validAccessToken()
            let token2 = try await auth.validAccessToken()
            req.setValue("Bearer \(token2)", forHTTPHeaderField: "Authorization")
            let (data2, response2) = try await session.data(for: req)
            guard let http2 = response2 as? HTTPURLResponse, (200..<300).contains(http2.statusCode) else {
                let body = String(data: data2, encoding: .utf8) ?? "<binary>"
                throw APIError.httpStatus((response2 as? HTTPURLResponse)?.statusCode ?? -1, body)
            }
            return try decoder.decode(T.self, from: data2)
        default:
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.httpStatus(http?.statusCode ?? -1, body)
        }
    }
}
