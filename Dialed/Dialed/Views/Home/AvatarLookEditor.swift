//
//  AvatarLookEditor.swift
//  Dialed
//
//  One avatar look (a mood, or "future you"): use a real photo instead of
//  the drawing. Pick or take one, lift yourself off the background, zoom
//  and slide it into place, or go back to the generated look. Also the
//  "Your looks" strip that opens it from the avatar sheet.
//

import SwiftUI
import PhotosUI

/// The looks you can swap for a photo, in display order.
enum AvatarLookSlot: String, CaseIterable, Identifiable {
    case onFire, lockedIn, gettingThere, runningOnEmpty, future

    var id: String { rawValue }

    var key: String { self == .future ? AvatarStudio.futureKey : rawValue }

    var mood: AvatarMood? { AvatarMood(rawValue: rawValue) }

    var title: String { mood.map { "\($0.emoji) \($0.title)" } ?? "✨ Future you" }

    var tint: Color { mood.map { Color(hex: $0.accentHex) } ?? Neka.lavender }
}

// MARK: - Your looks strip

struct AvatarYourLooksCard: View {
    @ObservedObject private var studio = AvatarStudio.shared
    @State private var editing: AvatarLookSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your looks")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                Text("Tap to use a real photo")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AvatarLookSlot.allCases) { slot in
                        Button { editing = slot } label: { tile(slot) }
                            .buttonStyle(.dialedScale)
                            .accessibilityLabel("\(slot.title) look, \(studio.source(for: slot.key).badge ?? "empty"). Edit.")
                    }
                }
                .padding(.vertical, 2)
            }
            Toggle(isOn: $studio.usePhotoLooks) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use my photos where I've added them")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Neka.ink)
                    Text("Off shows the drawings everywhere; your photos stay saved.")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            .tint(Neka.green)
        }
        .padding(16)
        .nekaCard()
        .sheet(item: $editing) { slot in
            AvatarLookEditor(slot: slot)
                .presentationDetents([.large])
        }
    }

    private func tile(_ slot: AvatarLookSlot) -> some View {
        let source = studio.source(for: slot.key)
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(slot.tint.opacity(0.14))
                if let image = studio.look(for: slot.key) {
                    FocusedImage(image: image)
                } else if studio.inProgress.contains(slot.key) {
                    ProgressView().tint(slot.tint)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(slot.tint)
                }
            }
            .frame(width: 84, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let badge = source.badge {
                    AvatarSourceBadge(text: badge, isPhoto: source == .photo).padding(6)
                }
            }
            Text(slot.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Neka.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 84)
        }
    }
}

/// "Photo" / "AI" chip on a look.
struct AvatarSourceBadge: View {
    let text: String
    let isPhoto: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isPhoto ? "camera.fill" : "sparkles")
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(isPhoto ? Neka.onInk : Neka.ink)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(isPhoto ? Neka.ink.opacity(0.85) : Neka.surface.opacity(0.9)))
    }
}

// MARK: - Editor

struct AvatarLookEditor: View {
    let slot: AvatarLookSlot

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var studio = AvatarStudio.shared
    @State private var framing = AvatarLookResolver.Framing()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var confirmRemove = false

    private var key: String { slot.key }
    private var hasPhoto: Bool { studio.hasPhotoLook(key) }
    private var busy: Bool { studio.inProgress.contains(key) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview
                    sourceButtons
                    if hasPhoto { adjustCard }
                    if hasPhoto {
                        Button(role: .destructive) { confirmRemove = true } label: {
                            Label(studio.images[key] == nil ? "Remove this photo" : "Back to the generated look",
                                  systemImage: "wand.and.sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Neka.track))
                        }
                        .foregroundColor(Neka.rose)
                    }
                    if !studio.usePhotoLooks && hasPhoto {
                        Label("\"Use my photos\" is off, so the drawing shows for now.", systemImage: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle(slot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .onAppear { framing = studio.photoFraming(for: key) }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await studio.setPhotoLook(data, for: key)
                    framing = studio.photoFraming(for: key)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { image in
                    showCamera = false
                    guard let image else { return }
                    Task {
                        await studio.setPhotoLook(image, for: key, framing: .init(cutout: framing.cutout))
                        framing = studio.photoFraming(for: key)
                    }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Go back to the generated look?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove photo", role: .destructive) {
                    withAnimation { studio.removePhotoLook(key) }
                    framing = AvatarLookResolver.Framing()
                }
            } message: {
                Text("Your photo for this look is deleted. The drawing (or a new one) takes its place.")
            }
        }
    }

    // MARK: - Pieces

    /// Shown the way Home's hero shows it: you, on a soft wash.
    private var preview: some View {
        let source = studio.source(for: key)
        return ZStack(alignment: .bottom) {
            LinearGradient(colors: [slot.tint.opacity(0.28), slot.tint.opacity(0.08)], startPoint: .top, endPoint: .bottom)
            if let image = studio.look(for: key) {
                if source == .photo && framing.cutout {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(.top, 20)
                } else {
                    FocusedImage(image: image)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(slot.tint)
                    Text("No look yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
                .frame(maxHeight: .infinity)
            }
            if busy {
                ProgressView()
                    .tint(Neka.ink)
                    .padding(14)
                    .background(Circle().fill(Neka.surface))
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let badge = source.badge {
                AvatarSourceBadge(text: badge, isPhoto: source == .photo).scaleEffect(1.3, anchor: .topLeading).padding(12)
            }
        }
        .animation(.easeOut(duration: 0.25), value: busy)
    }

    private var sourceButtons: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(hasPhoto ? "Change photo" : "Use a photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.nekaPrimary)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label("Take photo", systemImage: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
            }
        }
        .disabled(busy)
    }

    private var adjustCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { framing.cutout }, set: { framing.cutout = $0; apply() })) {
                Label("Cut out the background", systemImage: "person.and.background.dotted")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Neka.ink)
            }
            .tint(Neka.green)
            slider("Zoom", systemImage: "plus.magnifyingglass", value: $framing.scale,
                   range: AvatarLookResolver.Framing.scaleRange)
            slider("Position", systemImage: "arrow.up.and.down", value: $framing.offsetY,
                   range: AvatarLookResolver.Framing.offsetRange)
            Button("Reset framing") {
                framing.scale = 1
                framing.offsetY = 0
                apply()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .nekaCard()
        .disabled(busy)
    }

    private func slider(_ title: String, systemImage: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
            // Re-renders when you let go, not on every tick.
            Slider(value: value, in: range) { editing in
                if !editing { apply() }
            }
            .tint(slot.tint)
        }
    }

    private func apply() {
        let f = framing
        Task { await studio.updatePhotoLook(key, framing: f) }
    }
}
