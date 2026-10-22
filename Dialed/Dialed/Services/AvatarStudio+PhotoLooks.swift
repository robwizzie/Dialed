//
//  AvatarStudio+PhotoLooks.swift
//  Dialed
//
//  Real photos as avatar looks. Each look (a mood, or "future you") can
//  use a photo you pick or take instead of the drawing: optionally lifted
//  off its background with Vision (the same cutout as your Home photo),
//  cropped to 4:5 where you put it, and saved per look. The original is
//  kept so you can re-crop or toggle the cutout without picking again, and
//  so an AI look can be drawn from it.
//
//  Files live in Application Support/AvatarPhotos:
//    <key>-original.jpg — upright, downscaled photo you chose
//    <key>-cutout.png   — that photo lifted off its background (a cache)
//    <key>.png          — the cropped look (alpha when cut out)
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
    }

    /// The image a look is cropped from: the original, or you lifted off
    /// it (made once, then cached). Falls back to the original when Vision
    /// can't find you.
    func photoBase(for key: String, cutout: Bool) async -> UIImage? {
        let cacheKey = "\(key)|\(cutout ? "cutout" : "photo")"
        if let cached = photoBases[cacheKey] { return cached }
        guard let original = photoOriginal(for: key) else { return nil }
        guard cutout else {
            photoBases[cacheKey] = original
            return original
        }
        let url = Self.photoCutoutURL(for: key)
        let lifted: UIImage? = await Task.detached(priority: .userInitiated) {
            if let data = try? Data(contentsOf: url), let saved = UIImage(data: data) { return saved }
            guard let lifted = ProfilePhotoStore.liftSubject(from: original) else { return nil }
            try? lifted.pngData()?.write(to: url, options: .atomic)
            return lifted
        }.value
        let base = lifted ?? original
        photoBases[cacheKey] = base
        return base
    }

    // MARK: - Writing

    /// Use `image` as `key`'s look: keep the original, cut it out if asked,
    /// and start from a crop that fits you in. Returns that framing.
    @discardableResult
    func setPhotoLook(_ image: UIImage, for key: String, cutout: Bool = true) async -> AvatarLookResolver.Framing {
        inProgress.insert(key)
        defer { inProgress.remove(key) }
        let upright = await Task.detached(priority: .userInitiated) {
            Self.uprightPhoto(image, maxDimension: 1600)
        }.value
        try? FileManager.default.createDirectory(at: Self.photoDirectory, withIntermediateDirectories: true)
        try? upright.jpegData(compressionQuality: 0.9)?.write(to: Self.photoOriginalURL(for: key), options: .atomic)
        forgetPhotoBases(key)

        let base = await photoBase(for: key, cutout: cutout) ?? upright
        var framing = Self.startFraming(for: base)
        framing.cutout = cutout
        await renderPhotoLook(key, framing: framing)
        // A new photo shows itself, even if an AI look was showing before.
        prefersDrawing.remove(key)
        return framing
    }

    func setPhotoLook(_ data: Data, for key: String, cutout: Bool = true) async -> AvatarLookResolver.Framing? {
        guard let image = UIImage(data: data) else {
            lastError = "Couldn't read that photo. Try another one."
            return nil
        }
        return await setPhotoLook(image, for: key, cutout: cutout)
    }

    /// Re-crop (or toggle the cutout on) the photo already chosen.
    func updatePhotoLook(_ key: String, framing: AvatarLookResolver.Framing) async {
        await renderPhotoLook(key, framing: framing)
    }

    /// Back to the drawing.
    func removePhotoLook(_ key: String) {
        photoLooks[key] = nil
        prefersDrawing.remove(key)
        forgetPhotoBases(key)
        try? FileManager.default.removeItem(at: Self.photoLookURL(for: key))
        try? FileManager.default.removeItem(at: Self.photoOriginalURL(for: key))
        var framings = Self.storedFramings()
        framings[key] = nil
        Self.storeFramings(framings)
    }

    private func forgetPhotoBases(_ key: String) {
        photoBases["\(key)|cutout"] = nil
        photoBases["\(key)|photo"] = nil
        try? FileManager.default.removeItem(at: Self.photoCutoutURL(for: key))
    }

    private func renderPhotoLook(_ key: String, framing: AvatarLookResolver.Framing) async {
        let f = framing.clamped
        let token = (photoRenderTokens[key] ?? 0) + 1
        photoRenderTokens[key] = token
        guard let base = await photoBase(for: key, cutout: f.cutout) else { return }
        let look = await Task.detached(priority: .userInitiated) { Self.framed(base, framing: f) }.value
        // A newer crop was asked for while this one rendered.
        guard photoRenderTokens[key] == token else { return }

        photoLooks[key] = look
        var framings = Self.storedFramings()
        framings[key] = f
        Self.storeFramings(framings)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: Self.photoDirectory, withIntermediateDirectories: true)
            try? look.pngData()?.write(to: Self.photoLookURL(for: key), options: .atomic)
        }
    }

    // MARK: - AI looks from your photos

    /// Draws `key`'s AI look from the photo you set for it, and shows the
    /// drawing (your photo stays saved; switch back any time).
    func drawFromPhotoLook(_ key: String) async {
        guard let original = photoOriginal(for: key) else { return }
        useReference(original, for: [key])
        prefersDrawing.insert(key)
        await regenerate(key: key)
        // Nothing came back (and no Image Playground sheet took over).
        if images[key] == nil && sheetRequest == nil { prefersDrawing.remove(key) }
    }

    /// The moods that have a photo, drawn one after another. Stops if
    /// Image Playground needs you to confirm one in its own sheet.
    func drawMoodsFromPhotoLooks() async {
        for mood in AvatarMood.allCases where hasPhotoLook(mood.rawValue) {
            await drawFromPhotoLook(mood.rawValue)
            if sheetRequest != nil { break }
        }
    }

    /// Show the photo or the AI look drawn from it.
    func showDrawing(_ show: Bool, for key: String) {
        if show { prefersDrawing.insert(key) } else { prefersDrawing.remove(key) }
    }

    // MARK: - Image work

    /// Where a crop starts: a real cutout fits whole on the bottom edge;
    /// a photo (or a cutout Vision couldn't find you in) fills the frame.
    nonisolated static func startFraming(for base: UIImage) -> AvatarLookResolver.Framing {
        let alpha = base.cgImage?.alphaInfo
        let lifted = [.premultipliedLast, .premultipliedFirst, .last, .first].contains(alpha)
        return AvatarLookResolver.defaultFraming(width: Double(base.size.width), height: Double(base.size.height),
                                                 cutout: lifted)
    }

    /// The 4:5 crop, at most ~1250 px tall. Transparent where a zoomed-out
    /// cutout doesn't reach the edges.
    nonisolated static func framed(_ image: UIImage, framing: AvatarLookResolver.Framing) -> UIImage {
        let r = AvatarLookResolver.cropRect(width: Double(image.size.width), height: Double(image.size.height),
                                            framing: framing)
        let k = min(1, 1250 / r.height)
        let size = CGSize(width: (r.width * k).rounded(), height: (r.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(x: -r.x * k, y: -r.y * k,
                                  width: Double(image.size.width) * k, height: Double(image.size.height) * k))
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

    nonisolated static func photoCutoutURL(for key: String) -> URL {
        photoDirectory.appendingPathComponent("\(key)-cutout.png")
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
