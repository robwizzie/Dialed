//
//  OpenFoodFacts.swift
//  Dialed
//
//  Barcode → nutrition, from the free Open Food Facts database. Parsing
//  and the serving / gram math are plain functions (unit-tested); the
//  network call is a thin wrapper around them.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct FoodFactsNutrients: Equatable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    var isEmpty: Bool { calories == nil && protein == nil && carbs == nil && fat == nil }

    func scaled(by factor: Double) -> FoodFactsNutrients {
        FoodFactsNutrients(
            calories: calories.map { $0 * factor },
            protein: protein.map { $0 * factor },
            carbs: carbs.map { $0 * factor },
            fat: fat.map { $0 * factor }
        )
    }
}

struct FoodFactsProduct: Equatable {
    var code: String
    var name: String
    var brand: String?
    /// Label text, e.g. "1 bar (40 g)".
    var servingSize: String?
    /// Grams (or ml) in one serving, when known.
    var servingGrams: Double?
    var per100g: FoodFactsNutrients
    var perServing: FoodFactsNutrients

    /// "Brand Name" — brand first unless the name already starts with it.
    var displayName: String {
        guard let brand, !brand.isEmpty, !name.lowercased().hasPrefix(brand.lowercased()) else { return name }
        return "\(brand) \(name)"
    }

    var supportsServings: Bool {
        perServing.calories != nil || (servingGrams != nil && per100g.calories != nil)
    }

    var supportsGrams: Bool {
        per100g.calories != nil || (servingGrams != nil && perServing.calories != nil)
    }
}

/// How much was eaten.
enum FoodFactsPortion: Equatable {
    case servings(Double)
    case grams(Double)
}

extension FoodFactsProduct {
    /// Nutrients for a portion, preferring the label's own numbers.
    /// Nil when the product doesn't carry what that portion needs.
    func nutrients(for portion: FoodFactsPortion) -> FoodFactsNutrients? {
        switch portion {
        case .servings(let count):
            if perServing.calories != nil {
                return perServing.scaled(by: count)
            }
            if let grams = servingGrams, grams > 0, per100g.calories != nil {
                return per100g.scaled(by: grams * count / 100)
            }
            return nil
        case .grams(let grams):
            if per100g.calories != nil {
                return per100g.scaled(by: grams / 100)
            }
            if let serving = servingGrams, serving > 0, perServing.calories != nil {
                return perServing.scaled(by: grams / serving)
            }
            return nil
        }
    }

}

enum OpenFoodFacts {
    enum LookupError: LocalizedError, Equatable {
        case badCode
        case notFound
        case noNutrition
        case network

        var errorDescription: String? {
            switch self {
            case .badCode:     return "That doesn't look like a product barcode."
            case .notFound:    return "Open Food Facts doesn't know this product yet. Add it by hand."
            case .noNutrition: return "Found the product, but it has no calorie info. Add it by hand."
            case .network:     return "Couldn't reach Open Food Facts. Check your connection."
            }
        }
    }

    static let fields = "product_name,brands,nutriments,serving_size,serving_quantity"

    static func url(for code: String) -> URL? {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty, digits.count <= 14 else { return nil }
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=\(fields)")
    }

    /// Parse an API v2 product response.
    static func parse(_ data: Data, code: String) throws -> FoodFactsProduct {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let product = root["product"] as? [String: Any] else {
            throw LookupError.notFound
        }
        if let status = number(root["status"]), status == 0 { throw LookupError.notFound }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Double? { number(nutriments[key]) }
        func kcal(_ suffix: String) -> Double? {
            if let kcal = value("energy-kcal_\(suffix)") { return kcal }
            if let kj = value("energy-kj_\(suffix)") ?? value("energy_\(suffix)") { return kj / 4.184 }
            return nil
        }

        let per100g = FoodFactsNutrients(
            calories: kcal("100g"),
            protein: value("proteins_100g"),
            carbs: value("carbohydrates_100g"),
            fat: value("fat_100g")
        )
        let perServing = FoodFactsNutrients(
            calories: kcal("serving"),
            protein: value("proteins_serving"),
            carbs: value("carbohydrates_serving"),
            fat: value("fat_serving")
        )

        let rawName = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let servingSize = (product["serving_size"] as? String)?.trimmingCharacters(in: .whitespaces)
        let servingGrams = number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }

        let result = FoodFactsProduct(
            code: code,
            name: rawName.isEmpty ? (brand ?? "Scanned food") : rawName,
            brand: brand,
            servingSize: (servingSize?.isEmpty ?? true) ? nil : servingSize,
            servingGrams: servingGrams,
            per100g: per100g,
            perServing: perServing
        )
        guard result.supportsServings || result.supportsGrams else { throw LookupError.noNutrition }
        return result
    }

    static func lookup(_ code: String, session: URLSession = .shared) async throws -> FoodFactsProduct {
        guard let url = url(for: code) else { throw LookupError.badCode }
        var request = URLRequest(url: url)
        request.setValue("Dialed/1.0 (iOS; food logging)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LookupError.network
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { throw LookupError.notFound }
        return try parse(data, code: code.filter(\.isNumber))
    }

    /// Numbers arrive as JSON numbers or strings ("12.5").
    static func number(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let d as Double:   return d
        case let i as Int:      return Double(i)
        case let s as String:   return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        default:                return nil
        }
    }
}
