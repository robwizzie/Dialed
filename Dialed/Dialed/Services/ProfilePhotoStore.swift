//
//  ProfilePhotoStore.swift
//  Dialed
//
//  Your photo for the Home hero. On pick we lift the subject off the
//  background with Vision (iOS 17 foreground-instance masks, the same tech
//  as "lift subject" in Photos) so you float on the page like the reference
//  design. Falls back to the original photo when Vision can't run (the
//  simulator, or no person found).
//
//  Files live in Application Support:
//    profile-original.jpg  — downscaled original (avatar)
//    profile-cutout.png    — transparent subject cutout (hero)
//

import Foundation
import SwiftUI
import UIKit
import Vision
import CoreImage

@MainActor
final class ProfilePhotoStore: ObservableObject {
    static let shared = ProfilePhotoStore()

    @Published private(set) var original: UIImage?
    @Published private(set) var cutout: UIImage?
    @Published private(set) var isProcessing = false

    /// Pre-scaled copies so views never draw the 1600px original per frame.
    @Published private(set) var thumbnail: UIImage?
    @Published private(set) var heroDisplay: UIImage?

    /// Hero framing, tweakable from the profile sheet because every photo
    /// is cropped differently.
    @Published var heroScale: Double {
        didSet { UserDefaults.standard.set(heroScale, forKey: Keys.scale) }
    }
    @Published var heroOffsetY: Double {
        didSet { UserDefaults.standard.set(heroOffsetY, forKey: Keys.offsetY) }
    }

    private enum Keys {
        static let scale = "profilePhoto.heroScale"
        static let offsetY = "profilePhoto.heroOffsetY"
    }

    private init() {
        let defaults = UserDefaults.standard
        heroScale = defaults.object(forKey: Keys.scale) as? Double ?? 1.0
        heroOffsetY = defaults.object(forKey: Keys.offsetY) as? Double ?? 0
        original = Self.loadImage(Self.originalURL)
        cutout = Self.loadImage(Self.cutoutURL)
        rebuildDerived()
    }

    /// Hero prefers the cutout; avatar prefers the original.
    var heroImage: UIImage? { heroDisplay }
    var hasCutout: Bool { cutout != nil }

    // MARK: - Update

    func setPhoto(data: Data) async {
        guard let picked = UIImage(data: data) else { return }
        isProcessing = true
        defer { isProcessing = false }

        let upright = Self.normalized(picked, maxDimension: 1600)
        original = upright
        if let jpeg = upright.jpegData(compressionQuality: 0.88) {
            try? Self.write(jpeg, to: Self.originalURL)
        }

        let lifted = await Task.detached(priority: .userInitiated) {
            Self.liftSubject(from: upright)
        }.value

        cutout = lifted
        if let png = lifted?.pngData() {
            try? Self.write(png, to: Self.cutoutURL)
        } else {
            try? FileManager.default.removeItem(at: Self.cutoutURL)
        }
        heroScale = 1.0
        heroOffsetY = 0
        rebuildDerived()
        AvatarStudio.shared.clearAll()   // avatars were drawn from the old photo
    }

    func removePhoto() {
        original = nil
        cutout = nil
        rebuildDerived()
        AvatarStudio.shared.clearAll()
        try? FileManager.default.removeItem(at: Self.originalURL)
        try? FileManager.default.removeItem(at: Self.cutoutURL)
    }

    private func rebuildDerived() {
        thumbnail = original.map { Self.scaled($0, maxDimension: 160, opaque: true) }
        heroDisplay = (cutout ?? original).map { Self.scaled($0, maxDimension: 900, opaque: cutout == nil) }
    }

    /// Downscale so the longest side is `maxDimension` pixels.
    private static func scaled(_ image: UIImage, maxDimension: CGFloat, opaque: Bool) -> UIImage {
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let longest = max(pixelW, pixelH)
        guard longest > maxDimension else { return image }
        let ratio = maxDimension / longest
        let size = CGSize(width: (pixelW * ratio).rounded(), height: (pixelH * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Vision

    /// Returns the foreground subject cropped to its bounds with a
    /// transparent background, or nil if Vision finds nothing.
    nonisolated static func liftSubject(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let buffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            let context = CIContext()
            guard let output = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        } catch {
            return nil
        }
    }

    // MARK: - Files

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Profile", isDirectory: true)
    }

    private static var originalURL: URL { directory.appendingPathComponent("profile-original.jpg") }
    private static var cutoutURL: URL { directory.appendingPathComponent("profile-cutout.png") }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func loadImage(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Redraws the image upright (bakes in EXIF orientation) and caps its
    /// longest side, so Vision and the file on disk agree on pixels.
    private static func normalized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
