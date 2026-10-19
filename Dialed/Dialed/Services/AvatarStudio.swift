//
//  AvatarStudio.swift
//  Dialed
//
//  Turns your photo into illustrated avatars with Apple's on-device Image
//  Playground — one per mood (On fire, Locked in, Getting there, Running
//  on empty) plus a "future you" for your goal day. Images are generated
//  once and cached on disk; changing your photo clears them.
//
//  Generation tries the programmatic ImageCreator API (iOS 18.4+) first.
//  If Image Playground needs you to confirm the person yourself, it falls
//  back to presenting the system Image Playground sheet pre-filled with
//  the prompt (see `AvatarPlaygroundSheet`).
//

import SwiftUI
import UIKit
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

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "avatar.enabled")
        for key in AvatarMood.allCases.map(\.rawValue) + [Self.futureKey] {
            if let data = try? Data(contentsOf: Self.url(for: key)), let image = UIImage(data: data) {
                images[key] = image
            }
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
        guard let photo = ProfilePhotoStore.shared.original?.cgImage else {
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
              ProfilePhotoStore.shared.original != nil else { return }
        #if canImport(ImagePlayground)
        // Background fills use only the silent API — never pop a sheet.
        if #available(iOS 18.4, *) {
            let key = mood.rawValue
            guard !inProgress.contains(key), let photo = ProfilePhotoStore.shared.original?.cgImage else { return }
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
        if let data = image.pngData() {
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? data.write(to: Self.url(for: key), options: .atomic)
        }
    }

    /// Called when your photo changes — old avatars no longer match.
    func clearAll() {
        images = [:]
        try? FileManager.default.removeItem(at: Self.directory)
    }

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Avatars", isDirectory: true)
    }

    private static func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).png")
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
            sourceImage: ProfilePhotoStore.shared.original.map { Image(uiImage: $0) },
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
    func avatarPlaygroundSheet(_ studio: AvatarStudio = .shared) -> some View {
        modifier(AvatarPlaygroundSheet(studio: studio))
    }
}
