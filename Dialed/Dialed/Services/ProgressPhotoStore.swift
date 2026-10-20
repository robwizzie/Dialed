//
//  ProgressPhotoStore.swift
//  Dialed
//
//  Weekly progress photos, kept on this device only:
//    Application Support/ProgressPhotos/
//      index.json              — ProgressPhotoIndex (date, weight, note)
//      <uuid>.jpg              — the photo, portrait, max 1600 px tall
//      thumb-<uuid>.jpg        — 400 px thumbnail for the grid
//  Dialed never uploads these anywhere (they travel only inside your own
//  device backup). Files use complete file protection.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class ProgressPhotoStore: ObservableObject {
    static let shared = ProgressPhotoStore()

    @Published private(set) var index = ProgressPhotoIndex()

    private let folder: URL
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            index = ProgressPhotoIndex.decode(data)
        }
        cache.countLimit = 80
    }

    private var indexURL: URL { folder.appendingPathComponent("index.json") }
    private func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    var entries: [ProgressPhotoEntry] { index.entries }

    // MARK: - Images

    func image(for entry: ProgressPhotoEntry) -> UIImage? {
        load(entry.fileName)
    }

    func thumbnail(for entry: ProgressPhotoEntry) -> UIImage? {
        load(entry.thumbnailName) ?? image(for: entry)
    }

    private func load(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: url(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    // MARK: - Add / replace / delete

    /// Saves a new photo (or replaces `replacing`'s image, keeping its id).
    @discardableResult
    func add(_ image: UIImage, date: Date = Date(), weightLbs: Double?, note: String?, pose: ProgressPose? = nil,
             replacing: ProgressPhotoEntry? = nil) -> ProgressPhotoEntry? {
        let full = Self.resized(image, maxDimension: 1600)
        let thumb = Self.resized(image, maxDimension: 400)
        guard let fullData = full.jpegData(compressionQuality: 0.85),
              let thumbData = thumb.jpegData(compressionQuality: 0.8) else { return nil }

        var entry = replacing ?? ProgressPhotoEntry(date: date, weightLbs: weightLbs, note: note, pose: pose)
        if replacing != nil {
            entry.date = date
            entry.weightLbs = weightLbs ?? entry.weightLbs
            entry.note = note ?? entry.note
            entry.pose = pose ?? entry.pose
        }
        do {
            try fullData.write(to: url(entry.fileName), options: [.atomic, .completeFileProtection])
            try thumbData.write(to: url(entry.thumbnailName), options: [.atomic, .completeFileProtection])
        } catch {
            return nil
        }
        cache.removeObject(forKey: entry.fileName as NSString)
        cache.removeObject(forKey: entry.thumbnailName as NSString)
        index.add(entry)
        persist()
        return entry
    }

    func update(_ entry: ProgressPhotoEntry, weightLbs: Double?, note: String?) {
        index.update(id: entry.id, weightLbs: weightLbs, note: note)
        persist()
    }

    func delete(_ entry: ProgressPhotoEntry) {
        guard let removed = index.remove(id: entry.id) else { return }
        try? FileManager.default.removeItem(at: url(removed.fileName))
        try? FileManager.default.removeItem(at: url(removed.thumbnailName))
        cache.removeObject(forKey: removed.fileName as NSString)
        cache.removeObject(forKey: removed.thumbnailName as NSString)
        persist()
    }

    private func persist() {
        guard let data = try? index.encoded() else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtection])
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    // MARK: - Helpers

    /// Redraws upright (bakes in EXIF orientation) and downsizes.
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
