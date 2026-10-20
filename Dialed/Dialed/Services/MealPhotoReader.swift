//
//  MealPhotoReader.swift
//  Dialed
//
//  Looks at a meal photo on-device with Vision and returns the foods it
//  can see ("pizza", "salad", "steak"), most confident first. The names
//  then go to Apple Intelligence (DialedAI.estimateMeal) for calories,
//  protein, carbs and fat. Nothing leaves the phone.
//

import UIKit
import Vision

enum MealPhotoReader {
    /// Labels that describe the scene, not the food.
    private static let ignored: Set<String> = [
        "food", "dish", "meal", "cuisine", "tableware", "table", "plate", "bowl", "cup", "dining_table",
        "utensil", "fork", "knife", "spoon", "napkin", "placemat", "container", "indoor", "outdoor",
        "structure", "material", "wood_processed", "people", "adult", "hand", "finger", "art",
        "drink", "beverage", "produce", "baked_goods", "fast_food", "dessert", "snack", "ingredient"
    ]

    /// Foods Vision sees in the photo, as readable names, best first.
    static func foods(in image: UIImage, limit: Int = 6) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
                do {
                    try handler.perform([request])
                    let names = (request.results ?? [])
                        .filter { $0.confidence > 0.12 && !ignored.contains($0.identifier) }
                        .prefix(limit)
                        .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                    continuation.resume(returning: Array(names))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
