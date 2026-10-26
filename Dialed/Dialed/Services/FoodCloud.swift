//
//  FoodCloud.swift
//  Dialed
//
//  Meal reading and restaurant menus from your Dialed server
//  (challenge-worker/src/food.js), where Claude itemizes what you ate and
//  USDA FoodData Central prices the generic foods. Far more accurate than
//  the on-device model, so it's tried first whenever the server is set up;
//  DialedAI falls back to the food table and Apple Intelligence offline.
//
//  Uses the same server address and create key as the live challenge.
//

import Foundation

@MainActor
enum FoodCloud {

    // MARK: - Wire types

    struct Usual: Encodable {
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    private struct ParseRequest: Encodable {
        let text: String
        let image: String?
        let usuals: [Usual]
    }

    struct Item: Decodable {
        let name: String
        let amount: Double
        let unit: String
        let grams: Double
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        /// "usda" or "estimate".
        let source: String
        /// The usual it matched ("my usual cold brew"), if any.
        let usual: String?
    }

    struct Parsed: Decodable {
        let name: String
        let assumption: String
        let items: [Item]
    }

    struct MenuItem: Decodable, Hashable, Identifiable {
        let name: String
        let category: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        /// "No bun −150"-style swap, if there's a good one.
        let tip: String?
        var id: String { category + "|" + name }
    }

    struct Menu: Decodable {
        let restaurant: String
        /// False for a place without published nutrition: a typical menu, estimated.
        let known: Bool
        let items: [MenuItem]
    }

    private struct Failure: Decodable { let error: String }

    struct ServerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Setup

    private static var server: URL? {
        let raw = ChallengeSync.shared.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !raw.isEmpty else { return nil }
        return URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)")
    }

    private static var key: String { ChallengeSync.shared.createKey }

    /// Server address and key are both set (Challenge → Live sync).
    static var isConfigured: Bool { server != nil && !key.isEmpty }

    // MARK: - Calls

    /// Itemize a meal from words, a photo, or both. nil when the server
    /// isn't set up or the call fails (callers fall back on-device).
    static func parse(text: String, imageJPEG: Data? = nil, usuals: [Usual] = []) async -> Parsed? {
        guard isConfigured, let server else { return nil }
        var request = URLRequest(url: server.appendingPathComponent("api/food/parse"), timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-create-key")
        let body = ParseRequest(text: text, image: imageJPEG?.base64EncodedString(), usuals: Array(usuals.prefix(40)))
        request.httpBody = try? JSONEncoder().encode(body)
        guard let parsed: Parsed = try? await send(request), !parsed.items.isEmpty else { return nil }
        return parsed
    }

    private static var menus: [String: Menu] = [:]

    /// A restaurant's full menu. The server caches each chain for a month;
    /// the first fetch of a chain can take up to a minute.
    static func menu(for restaurant: String) async throws -> Menu {
        guard isConfigured, let server else {
            throw ServerError(message: "Add your Dialed server in Challenge → Live sync to see full menus.")
        }
        let cacheKey = restaurant.lowercased()
        if let cached = menus[cacheKey] { return cached }
        var components = URLComponents(url: server.appendingPathComponent("api/food/menu"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "chain", value: restaurant)]
        guard let url = components?.url else { throw ServerError(message: "Bad server address.") }
        var request = URLRequest(url: url, timeoutInterval: 150)
        request.setValue(key, forHTTPHeaderField: "x-create-key")
        let menu: Menu = try await send(request)
        menus[cacheKey] = menu
        return menu
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "HTTP \(status)"
            throw ServerError(message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Into Dialed's types

    /// The parsed meal as an itemized estimate the review screen can edit.
    static func estimate(_ parsed: Parsed) -> AIMealEstimate {
        let parts = parsed.items.map { item -> MealPart in
            let label: String
            if item.usual != nil {
                label = "your log"
            } else if item.source == "usda" {
                label = "USDA"
            } else {
                label = "estimated"
            }
            return MealPart(name: item.name, amount: MealMath.describe(item.amount, item.unit), grams: item.grams,
                            calories: item.calories, protein: item.protein, carbs: item.carbs, fat: item.fat,
                            fromTable: item.usual != nil || item.source == "usda", sourceLabel: label)
        }
        let total = { (key: KeyPath<MealPart, Double>) in Int(parts.reduce(0) { $0 + $1[keyPath: key] }.rounded()) }
        let grounded = parts.filter(\.fromTable).count
        let note = grounded == parts.count
            ? "Numbers from USDA and your log."
            : "\(grounded) of \(parts.count) items from USDA or your log; the rest estimated by Claude."
        return AIMealEstimate(name: parsed.name, calories: total(\.calories), proteinGrams: total(\.protein),
                              carbsGrams: total(\.carbs), fatGrams: total(\.fat),
                              assumption: [note, parsed.assumption].filter { !$0.isEmpty }.joined(separator: " "),
                              parts: parts, fromTable: grounded == parts.count)
    }
}
