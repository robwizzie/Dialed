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
    /// The image being cropped (original or cutout), drawn live.
    @State private var base: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var confirmRemove = false
    /// Framing when the current drag / pinch began.
    @State private var gestureStart: AvatarLookResolver.Framing?
    @State private var saveTask: Task<Void, Never>?

    private typealias Framing = AvatarLookResolver.Framing
    private static let canvasSize = CGSize(width: 280, height: 350)

    private var key: String { slot.key }
    private var hasPhoto: Bool { studio.hasPhotoLook(key) }
    private var busy: Bool { studio.inProgress.contains(key) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasPhoto {
                        cropCard
                    } else {
                        emptyPreview
                    }
                    sourceButtons
                    if hasPhoto {
                        adjustCard
                        aiCard
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
            .scrollDisabled(gestureStart != nil)
            .nekaPageBackground()
            .navigationTitle(slot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveNow()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                framing = studio.photoFraming(for: key)
                await loadBase()
                // Re-save on open so the look everywhere matches this crop
                // exactly (older looks were saved by different rules).
                saveNow()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    base = nil
                    if let f = await studio.setPhotoLook(data, for: key, cutout: framing.cutout) { framing = f }
                    await loadBase()
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { image in
                    showCamera = false
                    guard let image else { return }
                    Task {
                        base = nil
                        framing = await studio.setPhotoLook(image, for: key, cutout: framing.cutout)
                        await loadBase()
                    }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Go back to the generated look?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove photo", role: .destructive) {
                    saveTask?.cancel()
                    withAnimation { studio.removePhotoLook(key) }
                    framing = Framing()
                    base = nil
                }
            } message: {
                Text("Your photo for this look is deleted. The drawing (or a new one) takes its place.")
            }
        }
    }

    // MARK: - Crop

    /// The crop itself — drag to move, pinch to zoom, double-tap to start
    /// over — and the same crop in each place the look shows up.
    private var cropCard: some View {
        VStack(spacing: 14) {
            ZStack {
                wash
                if let base {
                    PhotoCropView(base: base, framing: framing)
                }
                if gestureStart != nil { thirdsGrid }
                if base == nil {
                    ProgressView()
                        .tint(Neka.ink)
                        .padding(14)
                        .background(Circle().fill(Neka.surface))
                }
            }
            .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(slot.tint.opacity(gestureStart == nil ? 0.35 : 0.9), lineWidth: 2)
            )
            .contentShape(Rectangle())
            .gesture(cropGesture)
            .onTapGesture(count: 2) { resetFraming() }
            .accessibilityElement()
            .accessibilityLabel("Crop for \(slot.title)")
            .accessibilityHint("Drag to move, pinch to zoom, double-tap to reset.")
            .animation(.easeOut(duration: 0.2), value: gestureStart == nil)

            Text("Drag to move · pinch to zoom · double-tap to reset")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Neka.inkTertiary)

            VStack(alignment: .leading, spacing: 8) {
                Text("HOW IT SHOWS UP")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(Neka.inkTertiary)
                HStack(alignment: .top, spacing: 12) {
                    placePreview("Home", size: CGSize(width: 74, height: 88), radius: 14)
                    placePreview("Mood card", size: CGSize(width: 102, height: 88), radius: 14)
                    placePreview("Badge", size: CGSize(width: 88, height: 88), radius: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .nekaCard()
    }

    private var wash: some View {
        LinearGradient(colors: [slot.tint.opacity(0.28), slot.tint.opacity(0.08)], startPoint: .top, endPoint: .bottom)
    }

    private var thirdsGrid: some View {
        Canvas { ctx, size in
            var path = Path()
            for i in 1...2 {
                let x = size.width * CGFloat(i) / 3
                let y = size.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 0.75)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func placePreview(_ title: String, size: CGSize, radius: CGFloat) -> some View {
        VStack(spacing: 5) {
            ZStack {
                wash
                if let base {
                    PhotoLookFill { PhotoCropView(base: base, framing: framing) }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
        }
        .accessibilityHidden(true)
    }

    private var cropGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .simultaneously(with: MagnifyGesture())
            .onChanged { value in
                guard let base else { return }
                let start = gestureStart ?? framing
                if gestureStart == nil { gestureStart = start }
                var f = start
                if let pinch = value.second { f.scale = start.scale * pinch.magnification }
                if let drag = value.first {
                    let iw = Double(base.size.width)
                    let ih = Double(base.size.height)
                    let r = AvatarLookResolver.cropRect(width: iw, height: ih, framing: start)
                    let shown = Double(Self.canvasSize.width)
                    f.offsetX = start.offsetX + AvatarLookResolver.offsetDelta(
                        dragPoints: drag.translation.width, image: iw, crop: r.width, cutout: start.cutout,
                        cropWidth: r.width, shownWidth: shown)
                    f.offsetY = start.offsetY + AvatarLookResolver.offsetDelta(
                        dragPoints: drag.translation.height, image: ih, crop: r.height, cutout: start.cutout,
                        cropWidth: r.width, shownWidth: shown)
                }
                framing = f.clamped
            }
            .onEnded { _ in
                gestureStart = nil
                save()
            }
    }

    /// Before a photo: the look as it is now (drawing, or nothing yet).
    private var emptyPreview: some View {
        ZStack {
            wash
            if let image = studio.look(for: key) {
                FocusedImage(image: image)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(slot.tint)
                    Text("No look yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            if busy {
                ProgressView()
                    .tint(Neka.ink)
                    .padding(14)
                    .background(Circle().fill(Neka.surface))
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let badge = studio.source(for: key).badge {
                AvatarSourceBadge(text: badge, isPhoto: false).scaleEffect(1.3, anchor: .topLeading).padding(12)
            }
        }
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
            Toggle(isOn: Binding(get: { framing.cutout }, set: { setCutout($0) })) {
                Label("Cut out the background", systemImage: "person.and.background.dotted")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Neka.ink)
            }
            .tint(Neka.green)
            VStack(alignment: .leading, spacing: 6) {
                Label("Zoom", systemImage: "plus.magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                // The crop above follows live; the look saves when you let go.
                Slider(value: Binding(get: { framing.scale }, set: { framing.scale = $0; framing = framing.clamped }),
                       in: framing.minScale...Framing.maxScale) { editing in
                    if !editing { save() }
                }
                .tint(slot.tint)
            }
            Button("Reset crop") { resetFraming() }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .nekaCard()
        .disabled(busy || base == nil)
    }

    // MARK: - AI look

    /// Draw an AI look from this photo, and pick which one shows.
    private var aiCard: some View {
        let drawing = studio.images[key]
        let showsDrawing = studio.source(for: key) == .generated
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.lavenderSoft)
                    if let drawing {
                        FocusedImage(image: drawing)
                    } else {
                        Image(systemName: "wand.and.sparkles")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Neka.lavender)
                    }
                    if busy && base != nil {
                        ProgressView().tint(Neka.ink)
                    }
                }
                .frame(width: 56, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI look from this photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(drawing == nil
                         ? "Image Playground draws this mood from your photo. Your photo stays saved."
                         : "Drawn from your photo. Show whichever you like.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if drawing != nil {
                Picker("Show", selection: Binding(get: { showsDrawing }, set: { studio.showDrawing($0, for: key) })) {
                    Text("My photo").tag(false)
                    Text("AI look").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!studio.usePhotoLooks)
            }
            if studio.canGenerate {
                Button {
                    saveNow()
                    dismiss()
                    // Runs from the avatar sheet, which can show Image
                    // Playground if it needs you to confirm the person.
                    Task { await studio.drawFromPhotoLook(key) }
                } label: {
                    Label(drawing == nil ? "Draw an AI look from this photo" : "Redraw from this photo",
                          systemImage: "wand.and.sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Neka.surface))
                        .overlay(Capsule().stroke(Neka.hairline, lineWidth: 1))
                }
                .buttonStyle(.dialedScale)
                .disabled(busy)
            } else {
                Label("AI looks need Image Playground (Apple Intelligence) on this iPhone.", systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(16)
        .nekaCard(wash: .lavender)
    }

    // MARK: - Actions

    private func loadBase() async {
        guard hasPhoto else { return }
        base = await studio.photoBase(for: key, cutout: framing.cutout)
    }

    private func setCutout(_ on: Bool) {
        framing.cutout = on
        base = nil
        Task {
            await loadBase()
            if let base {
                framing = AvatarStudio.startFraming(for: base)
                framing.cutout = on
            }
            saveNow()
        }
    }

    private func resetFraming() {
        guard let base else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            let cutout = framing.cutout
            framing = AvatarStudio.startFraming(for: base)
            framing.cutout = cutout
        }
        save()
    }

    /// Saves the crop shortly after you stop, so quick tweaks save once.
    private func save() {
        saveTask?.cancel()
        let f = framing
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await studio.updatePhotoLook(key, framing: f)
        }
    }

    private func saveNow() {
        guard hasPhoto else { return }
        saveTask?.cancel()
        let f = framing
        Task { await studio.updatePhotoLook(key, framing: f) }
    }
}
