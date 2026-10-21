//
//  WakeAlarmReference.swift
//  Dialed
//
//  The spot you photograph to beat the photo mission (the bathroom sink,
//  the coffee maker…). Stores a Vision feature print of the reference and
//  a thumbnail; at the alarm, a new photo is compared by feature-print
//  distance (PhotoMatch decides what's close enough).
//

import UIKit
import Vision

enum WakeAlarmReference {

    private static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var printURL: URL { folder.appendingPathComponent("wake-alarm-reference.print") }
    private static var imageURL: URL { folder.appendingPathComponent("wake-alarm-reference.jpg") }

    static var thumbnail: UIImage? { UIImage(contentsOfFile: imageURL.path) }

    /// Save `image` as the reference. False if Vision couldn't read it.
    @discardableResult
    static func save(_ image: UIImage) -> Bool {
        guard let print = featurePrint(image),
              let data = try? NSKeyedArchiver.archivedData(withRootObject: print, requiringSecureCoding: true) else { return false }
        do {
            try data.write(to: printURL, options: .atomic)
            try image.jpegData(compressionQuality: 0.6)?.write(to: imageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: printURL)
        try? FileManager.default.removeItem(at: imageURL)
    }

    /// How far `image` is from the reference (lower = more alike), or nil.
    static func distance(to image: UIImage) -> Float? {
        guard let data = try? Data(contentsOf: printURL),
              let reference = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data),
              let print = featurePrint(image) else { return nil }
        var distance: Float = 0
        do {
            try reference.computeDistance(&distance, to: print)
            return distance
        } catch {
            return nil
        }
    }

    private static func featurePrint(_ image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation(image.imageOrientation), options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    private static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
