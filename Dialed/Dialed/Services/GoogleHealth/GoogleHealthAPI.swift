//
//  GoogleHealthAPI.swift
//  Dialed
//
//  Thin client for health.googleapis.com/v4. Two read shapes cover
//  everything Dialed needs:
//    • list        GET  users/me/dataTypes/{type}/dataPoints?filter=…
//    • dailyRollUp POST users/me/dataTypes/{type}/dataPoints:dailyRollUp
//

import Foundation

@MainActor
final class GoogleHealthAPI {
    static let shared = GoogleHealthAPI()

    private let auth = GoogleHealthAuth.shared
    private let session: URLSession = .shared

    enum APIError: LocalizedError {
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .http(let status, let body):
                if status == 403 {
                    return "Google Health refused access (403). Make sure the Google Health API is enabled and you linked your Google account in the Google Health app."
                }
                return "Google Health error \(status): \(body.prefix(200))"
            }
        }
    }

    // MARK: - Reads

    /// Raw data points of one type, following pagination (capped).
    func list(_ dataType: String, filter: String?, pageSize: Int = 500, maxPages: Int = 4) async throws -> [GHDataPoint] {
        var all: [GHDataPoint] = []
        var pageToken: String?
        for _ in 0..<maxPages {
            var components = URLComponents(string: "\(GoogleHealthConfig.apiBase.absoluteString)users/me/dataTypes/\(dataType)/dataPoints")!
            var items = [URLQueryItem(name: "pageSize", value: String(pageSize))]
            if let filter { items.append(URLQueryItem(name: "filter", value: filter)) }
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            // Strict encoding: filter values contain quotes, spaces, >= and colons.
            components.percentEncodedQueryItems = items.map {
                URLQueryItem(name: $0.name, value: $0.value.map { Self.strictEncode($0) })
            }
            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            let page: GHListResponse = try await send(request)
            all += page.dataPoints ?? []
            guard let next = page.nextPageToken, !next.isEmpty else { break }
            pageToken = next
        }
        return all
    }

    /// The first page of a type as raw JSON — for the Devices diagnostic, to
    /// see exactly which fields Google sends.
    func rawList(_ dataType: String, filter: String?, pageSize: Int = 1) async throws -> String {
        var components = URLComponents(string: "\(GoogleHealthConfig.apiBase.absoluteString)users/me/dataTypes/\(dataType)/dataPoints")!
        var items = [URLQueryItem(name: "pageSize", value: String(pageSize))]
        if let filter { items.append(URLQueryItem(name: "filter", value: filter)) }
        components.percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.name, value: $0.value.map { Self.strictEncode($0) })
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let raw: RawJSON = try await send(request)
        return raw.text
    }

    /// Daily totals for `days` days ending today (inclusive).
    func dailyRollUp(_ dataType: String, days: Int, calendar: Calendar = .current) async throws -> [GHDailyRollUpResponse.Point] {
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let body = GHDailyRollUpRequest(
            range: .init(start: GHCivilDateTime(date: GHDate(start)), end: GHCivilDateTime(date: GHDate(end))),
            windowSizeDays: 1
        )
        var request = URLRequest(url: URL(string: "\(GoogleHealthConfig.apiBase.absoluteString)users/me/dataTypes/\(dataType)/dataPoints:dailyRollUp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let response: GHDailyRollUpResponse = try await send(request)
        return response.rollupDataPoints ?? []
    }

    nonisolated private static func strictEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Transport

    private func send<T: Decodable>(_ base: URLRequest) async throws -> T {
        var request = base
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")

        var (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            // Token rejected early — force one refresh and retry.
            request.setValue("Bearer \(try await auth.validAccessToken(forceRefresh: true))", forHTTPHeaderField: "Authorization")
            (data, response) = try await session.data(for: request)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        if T.self == RawJSON.self, let raw = RawJSON(data: data) as? T { return raw }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// A response body kept as pretty-printed text.
struct RawJSON: Decodable {
    let text: String

    init(data: Data) {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            text = String(data: pretty, encoding: .utf8) ?? ""
        } else {
            text = String(data: data, encoding: .utf8) ?? ""
        }
    }

    init(from decoder: Decoder) throws { text = "" }
}
