//
//  AvatarStudio.swift
//  Dialed
//
//  Turns your photo into illustrated avatars with Apple's on-device Image
//  Playground — one per mood (On fire, Locked in, Getting there, Running
//  on empty) plus a "future you" for your goal day. Images are generated
//  once and cached on disk; changing your photo clears them.
//
//  Each look can use its own reference photo (say, a gym selfie for
//  "Locked in" and a suit photo for "future you"). Looks without one use
//  your profile photo; changing that only clears the looks that use it.
//
//  Generation tries the programmatic ImageCreator API (iOS 18.4+) first.
//  If Image Playground needs you to confirm the person yourself, it falls
//  back to presenting the system Image Playground sheet pre-filled with
//  the prompt (see `AvatarPlaygroundSheet`).
//

import SwiftUI
import UIKit
import Vision
#if canImport(ImagePlayground)
import ImagePlayground
#endif

@MainActor
final class AvatarStudio: ObservableObject {
    static let shared = AvatarStudio()

    static let futureKey = "future"

    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var inProgress: Set<String> = []
    @Published var lastError: String?
    /// Where the face sits in each avatar (unit coordinates, top-left
    /// origin), so views can frame it instead of center-cropping.
    @Published private(set) var focusPoints: [String: CGPoint] = [:]
    /// Per-look reference photos, keyed like `images`.
    @Published private(set) var references: [String: UIImage] = [:]

    /// Set when generation needs the interactive Image Playground sheet.
    @Published var sheetRequest: SheetRequest?
    /// Key the most recent sheet was opened for (survives the sheet's
    /// dismissal so its completion can still store the image).
    private(set) var lastSheetKey: String?

    struct SheetRequest: Identifiable, Equatable {
        let id = UUID()
        let key: String
        let prompt: String
    }

    /// Once you've made your first avatar, other moods fill in on their own.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "avatar.enabled") }
    }

    static let allKeys = AvatarMood.allCases.map(\.rawValue) + [futureKey]

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "avatar.enabled")
        for key in Self.allKeys {
            if let data = try? Data(contentsOf: Self.url(for: key)), let image = UIImage(data: data) {
                images[key] = image
                locateFocus(of: image, key: key)
            }
            if let data = try? Data(contentsOf: Self.referenceURL(for: key)), let image = UIImage(data: data) {
                references[key] = image
            }
        }
    }

    // MARK: - Reference photos

    /// The photo a look is drawn from: its own reference, else your profile photo.
    func referencePhoto(for key: String) -> UIImage? {
        references[key] ?? ProfilePhotoStore.shared.original
    }

    func hasCustomReference(_ key: String) -> Bool { references[key] != nil }

    /// Use `data` as the reference for one look (or every look when `key`
    /// is nil), then redraw it.
    func setReference(_ data: Data, for key: String?) async {
        guard let image = UIImage(data: data).map(Self.downscaled) else {
            lastError = "Couldn't read that photo. Try another one."
            return
        }
        let keys = key.map { [$0] } ?? Self.allKeys
        try? FileManager.default.createDirectory(at: Self.referenceDirectory, withIntermediateDirectories: true)
        let jpeg = image.jpegData(compressionQuality: 0.9)
        for k in keys {
            references[k] = image
            try? jpeg?.write(to: Self.referenceURL(for: k), options: .atomic)
            removeImage(k)
        }
        if let key {
            await regenerate(key: key)
        } else if let mood = AvatarMood.allCases.first {
            // Redraw one now; the rest fill in as each mood comes up.
            await regenerate(key: mood.rawValue)
        }
    }

    /// Go back to the profile photo for one look.
    func clearReference(for key: String) async {
        references[key] = nil
        try? FileManager.default.removeItem(at: Self.referenceURL(for: key))
        removeImage(key)
        await regenerate(key: key)
    }

    /// Draw a look again from its reference photo.
    func regenerate(key: String) async {
        if key == Self.futureKey {
            await generateFuture(event: GoalEvent.load())
        } else if let mood = AvatarMood(rawValue: key) {
            await generate(mood: mood)
        }
    }

    func removeImage(_ key: String) {
        images[key] = nil
        focusPoints[key] = nil
        try? FileManager.default.removeItem(at: Self.url(for: key))
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 1536
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Capability

    /// Image Playground is available on this device (Apple Intelligence on).
    var canGenerate: Bool {
        #if canImport(ImagePlayground)
        if #available(iOS 18.1, *) {
            return ImagePlaygroundViewController.isAvailable
        }
        #endif
        return false
    }

    // MARK: - Prompts

    static func prompt(for mood: AvatarMood) -> String {
        "A friendly illustrated portrait of this person, \(mood.prompt)"
    }

    static func futurePrompt(event: GoalEvent?) -> String {
        let place = event.map { "at \($0.name.lowercased())" } ?? "at a celebration"
        return "A friendly illustrated portrait of this person wearing a sharp tailored suit \(place), confident and happy, warm string lights"
    }

    // MARK: - Generate

    func image(for mood: AvatarMood) -> UIImage? { images[mood.rawValue] }
    var futureImage: UIImage? { images[Self.futureKey] }

    func generate(mood: AvatarMood) async {
        await generate(key: mood.rawValue, prompt: Self.prompt(for: mood))
    }

    func generateFuture(event: GoalEvent?) async {
        await generate(key: Self.futureKey, prompt: Self.futurePrompt(event: event))
    }

    func generate(key: String, prompt: String) async {
        guard !inProgress.contains(key) else { return }
        guard let photo = referencePhoto(for: key)?.cgImage else {
            lastError = "Add a photo of yourself first (tap your picture on Home)."
            return
        }
        lastError = nil
        isEnabled = true

        #if canImport(ImagePlayground)
        if #available(iOS 18.4, *) {
            inProgress.insert(key)
            defer { inProgress.remove(key) }
            do {
                let creator = try await ImageCreator()
                let results = creator.images(for: [.image(photo), .text(prompt)], style: .animation, limit: 1)
                for try await created in results {
                    store(UIImage(cgImage: created.cgImage), key: key)
                    return
                }
            } catch {
                // Usually: Image Playground wants you to confirm the person
                // in its own sheet. Hand off to it with the same prompt.
                if canGenerate {
                    lastSheetKey = key
                    sheetRequest = SheetRequest(key: key, prompt: prompt)
                } else {
                    lastError = error.localizedDescription
                }
            }
            return
        }
        if #available(iOS 18.1, *), canGenerate {
            lastSheetKey = key
            sheetRequest = SheetRequest(key: key, prompt: prompt)
            return
        }
        #endif
        lastError = "Avatars need Image Playground (Apple Intelligence on iOS 18.1+)."
    }

    /// Fill in the current mood in the background once avatars are on.
    func ensure(mood: AvatarMood) async {
        guard isEnabled, images[mood.rawValue] == nil, canGenerate,
              referencePhoto(for: mood.rawValue) != nil else { return }
        #if canImport(ImagePlayground)
        // Background fills use only the silent API — never pop a sheet.
        if #available(iOS 18.4, *) {
            let key = mood.rawValue
            guard !inProgress.contains(key), let photo = referencePhoto(for: key)?.cgImage else { return }
            inProgress.insert(key)
            defer { inProgress.remove(key) }
            if let creator = try? await ImageCreator() {
                let results = creator.images(for: [.image(photo), .text(Self.prompt(for: mood))], style: .animation, limit: 1)
                do {
                    for try await created in results {
                        store(UIImage(cgImage: created.cgImage), key: key)
                        return
                    }
                } catch {}
            }
        }
        #endif
    }

    // MARK: - Storage

    func storeFromFile(_ url: URL) {
        guard let key = lastSheetKey,
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return }
        store(image, key: key)
        lastSheetKey = nil
    }

    private func store(_ image: UIImage, key: String) {
        images[key] = image
        locateFocus(of: image, key: key)
        if let data = image.pngData() {
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? data.write(to: Self.url(for: key), options: .atomic)
        }
    }

    /// Called when your profile photo changes. Looks drawn from it no
    /// longer match; looks with their own reference photo stay.
    func clearAll() {
        for key in Self.allKeys where references[key] == nil {
            removeImage(key)
        }
    }

    // MARK: - Framing

    /// Focus point for an image this studio made, or nil (frame centered).
    func focus(of image: UIImage) -> CGPoint? {
        guard let key = images.first(where: { $0.value === image })?.key else { return nil }
        return focusPoints[key]
    }

    private func locateFocus(of image: UIImage, key: String) {
        guard let cg = image.cgImage else { return }
        Task.detached(priority: .utility) {
            let point = Self.detectFocus(cg)
            await MainActor.run {
                // Ignore results for an image that has since been replaced.
                if let point, self.images[key]?.cgImage === cg { self.focusPoints[key] = point }
            }
        }
    }

    /// Largest face, else the head end of the largest person; nil if
    /// Vision finds neither (illustrations sometimes slip past it).
    nonisolated static func detectFocus(_ cg: CGImage) -> CGPoint? {
        let faces = VNDetectFaceRectanglesRequest()
        let people = VNDetectHumanRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([faces, people])
        func area(_ r: CGRect) -> CGFloat { r.width * r.height }
        // Vision boxes are normalized with a bottom-left origin.
        if let face = faces.results?.max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            let b = face.boundingBox
            return CGPoint(x: b.midX, y: 1 - b.midY)
        }
        if let person = people.results?.max(by: { area($0.boundingBox) < area($1.boundingBox) }) {
            let b = person.boundingBox
            return CGPoint(x: b.midX, y: 1 - (b.maxY - b.height * 0.15))
        }
        return nil
    }

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Avatars", isDirectory: true)
    }

    private static func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).png")
    }

    private static var referenceDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AvatarReferences", isDirectory: true)
    }

    private static func referenceURL(for key: String) -> URL {
        referenceDirectory.appendingPathComponent("\(key).jpg")
    }
}

// MARK: - Interactive fallback sheet

/// Presents the system Image Playground sheet when AvatarStudio asks for
/// it. No-op on devices without Image Playground.
struct AvatarPlaygroundSheet: ViewModifier {
    @ObservedObject var studio: AvatarStudio

    func body(content: Content) -> some View {
        #if canImport(ImagePlayground)
        if #available(iOS 18.1, *) {
            content.modifier(AvatarPlaygroundSheetInner(studio: studio))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if canImport(ImagePlayground)
@available(iOS 18.1, *)
private struct AvatarPlaygroundSheetInner: ViewModifier {
    @ObservedObject var studio: AvatarStudio

    func body(content: Content) -> some View {
        content.imagePlaygroundSheet(
            isPresented: Binding(
                get: { studio.sheetRequest != nil },
                set: { if !$0 { studio.sheetRequest = nil } }
            ),
            concepts: studio.sheetRequest.map { [ImagePlaygroundConcept.text($0.prompt)] } ?? [],
            sourceImage: studio.sheetRequest.flatMap { studio.referencePhoto(for: $0.key) }.map { Image(uiImage: $0) },
            onCompletion: { url in
                studio.storeFromFile(url)
            },
            onCancellation: {
                studio.sheetRequest = nil
            }
        )
    }
}
#endif

extension View {
    @MainActor
    func avatarPlaygroundSheet(_ studio: AvatarStudio? = nil) -> some View {
        modifier(AvatarPlaygroundSheet(studio: studio ?? .shared))
    }
}
