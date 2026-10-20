//
//  AvatarStudio+PhotoLooks.swift
//  Dialed
//
//  Real photos as avatar looks. Each look (a mood, or "future you") can
//  use a photo you pick or take instead of the drawing: optionally lifted
//  off its background with Vision (the same cutout as your Home photo),
//  zoomed and slid into place, and saved per look. The original is kept
//  so you can re-frame or toggle the cutout without picking again.
//
//  Files live in Application Support/AvatarPhotos:
//    <key>-original.jpg — upright, downscaled photo you chose
//    <key>.png          — the framed look (alpha when cut out)
//  Framing per look is in UserDefaults ("avatar.photoLooks.framing").
//

import UIKit

extension AvatarStudio {

    // MARK: - Reading

    func hasPhotoLook(_ key: String) -> Bool { photoLooks[key] != nil }

    func photoOriginal(for key: String) -> UIImage? {
        (try? Data(contentsOf: Self.photoOriginalURL(for: key))).flatMap(UIImage.init(data:))
    }

    func photoFraming(for key: String) -> AvatarLookResolver.Framing {
        Self.storedFramings()[key] ?? AvatarLookResolver.Framing()
    }

    /// Called from init for each look key.
    func loadPhotoLook(_ key: String) {
        guard let data = try? Data(contentsOf: Self.photoLookURL(for: key)),
              let image = UIImage(data: data) else { return }
        photoLooks[key] = image
        locatePhotoFocus(of: image, key: key)
    }

    // MARK: - Writing

    /// Use `image` as `key`'s look: keep the original, then cut out and
    /// frame it.
    func setPhotoLook(_ image: UIImage, for key: String, framing: AvatarLookResolver.Framing = .init()) async {
        let upright = Self.uprightPhoto(image, maxDimension: 1600)
        if let jpeg = upright.jpegData(compressionQuality: 0.9) {
            try? FileManager.default.createDirectory(at: Self.photoDirectory, withIntermediateDirectories: true)
            try? jpeg.write(to: Self.photoOriginalURL(for: key), options: .atomic)
        }
        await renderPhotoLook(from: upright, key: key, framing: framing)
    }

    func setPhotoLook(_ data: Data, for key: String) async {
        guard let image = UIImage(data: data) else {
            lastError = "Couldn't read that photo. Try another one."
            return
        }
        await setPhotoLook(image, for: key, framing: photoFraming(for: key))
    }

    /// Re-frame (or toggle the cutout on) the photo already chosen.
    func updatePhotoLook(_ key: String, framing: AvatarLookResolver.Framing) async {
        guard let original = photoOriginal(for: key) else { return }
        await renderPhotoLook(from: original, key: key, framing: framing)
    }

    /// Back to the drawing.
    func removePhotoLook(_ key: String) {
        photoLooks[key] = nil
        photoFocusPoints[key] = nil
        try? FileManager.default.removeItem(at: Self.photoLookURL(for: key))
        try? FileManager.default.removeItem(at: Self.photoOriginalURL(for: key))
        var framings = Self.storedFramings()
        framings[key] = nil
        Self.storeFramings(framings)
    }

    private func renderPhotoLook(from original: UIImage, key: String, framing: AvatarLookResolver.Framing) async {
        let f = framing.clamped
        inProgress.insert(key)
        defer { inProgress.remove(key) }
        let look = await Task.detached(priority: .userInitiated) { () -> UIImage in
            let base = f.cutout ? (ProfilePhotoStore.liftSubject(from: original) ?? original) : original
            return Self.framed(base, framing: f)
        }.value

        photoLooks[key] = look
        locatePhotoFocus(of: look, key: key)
        try? FileManager.default.createDirectory(at: Self.photoDirectory, withIntermediateDirectories: true)
        try? look.pngData()?.write(to: Self.photoLookURL(for: key), options: .atomic)
        var framings = Self.storedFramings()
        framings[key] = f
        Self.storeFramings(framings)
    }

    // MARK: - Image work

    /// Crop to the framing (keeps transparency for cutouts).
    nonisolated static func framed(_ image: UIImage, framing: AvatarLookResolver.Framing) -> UIImage {
        let size = image.size
        let r = AvatarLookResolver.cropRect(width: Double(size.width), height: Double(size.height), framing: framing)
        let crop = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        guard framing.scale > 1.001 || abs(framing.offsetY) > 0.001 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: crop.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -crop.minX, y: -crop.minY))
        }
    }

    /// Bakes in EXIF orientation and caps the longest side.
    nonisolated static func uprightPhoto(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func locatePhotoFocus(of image: UIImage, key: String) {
        guard let cg = image.cgImage else { return }
        Task.detached(priority: .utility) {
            let point = Self.detectFocus(cg)
            await MainActor.run {
                if let point, self.photoLooks[key]?.cgImage === cg { self.photoFocusPoints[key] = point }
            }
        }
    }

    // MARK: - Files

    nonisolated static var photoDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AvatarPhotos", isDirectory: true)
    }

    nonisolated static func photoLookURL(for key: String) -> URL {
        photoDirectory.appendingPathComponent("\(key).png")
    }

    nonisolated static func photoOriginalURL(for key: String) -> URL {
        photoDirectory.appendingPathComponent("\(key)-original.jpg")
    }

    private static let framingKey = "avatar.photoLooks.framing"

    private static func storedFramings() -> [String: AvatarLookResolver.Framing] {
        guard let data = UserDefaults.standard.data(forKey: framingKey),
              let map = try? JSONDecoder().decode([String: AvatarLookResolver.Framing].self, from: data) else { return [:] }
        return map
    }

    private static func storeFramings(_ map: [String: AvatarLookResolver.Framing]) {
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: framingKey) }
    }
}
