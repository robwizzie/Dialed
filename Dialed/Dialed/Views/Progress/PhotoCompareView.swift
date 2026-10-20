//
//  PhotoCompareView.swift
//  Dialed
//
//  Two progress photos with what your body measured at each: a wipe you
//  drag across, side by side, or the newer photo with the older one as a
//  ghost on top. Each is labeled with its date, trend weight, scale weight
//  and body fat; the header sums up the change ("−8.4 lb trend · −2.1%
//  body fat · 6 weeks"). Pinch zooms both photos together. Pick photos
//  from the strip below; Share renders a labeled side-by-side image —
//  nothing leaves your phone unless you send it.
//

import SwiftUI
import SwiftData

struct PhotoCompareView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var store = ProgressPhotoStore.shared
    @State private var beforeID: UUID
    @State private var afterID: UUID
    @State private var mode: Mode = .wipe
    @State private var split: CGFloat = 0.5
    @State private var ghost: Double = 0.5
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var picking: Slot = .before
    @State private var data = PhotoStatsData()
    @State private var shareImage: Image?

    enum Mode: String, CaseIterable, Identifiable {
        case wipe, sideBySide, overlay
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wipe:       return "Slider"
            case .sideBySide: return "Side by side"
            case .overlay:    return "Overlay"
            }
        }
    }

    enum Slot: String, CaseIterable, Identifiable {
        case before, after
        var id: String { rawValue }
        var title: String { self == .before ? "Before" : "After" }
    }

    init(before: ProgressPhotoEntry, after: ProgressPhotoEntry) {
        _beforeID = State(initialValue: before.id)
        _afterID = State(initialValue: after.id)
    }

    private var before: ProgressPhotoEntry? { store.index.entry(id: beforeID) }
    private var after: ProgressPhotoEntry? { store.index.entry(id: afterID) }
    private var scale: CGFloat { min(4, max(1, zoom * pinch)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.title).tag(m) }
                }
                .pickerStyle(.segmented)

                if let before, let after {
                    Group {
                        switch mode {
                        case .wipe:
                            wipe(before: before, after: after)
                        case .sideBySide:
                            HStack(spacing: 8) {
                                labeled(before, title: "Before")
                                labeled(after, title: "After")
                            }
                        case .overlay:
                            overlay(before: before, after: after)
                        }
                    }
                    .simultaneousGesture(zoomGesture)
                    .onTapGesture(count: 2) { withAnimation(.spring(response: 0.3)) { zoom = 1 } }

                    if scale > 1.01 {
                        Text("Pinch to zoom both · double-tap to reset")
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkTertiary)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("Pick two photos to compare.")
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkTertiary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }

                scrubber
                shareRow
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .task { data = await PhotoStatsData.load(for: store.entries, context: context) }
        .task(id: "\(beforeID)-\(afterID)-\(data.series.count)-\(data.bodyFat.count)") { renderShareImage() }
    }

    // MARK: - Summary

    private var delta: PhotoStats.Delta? {
        guard let before, let after else { return nil }
        return PhotoStats.delta(from: data.stats(for: before), at: before.date,
                                to: data.stats(for: after), at: after.date)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let delta {
                Text(PhotoStats.span(delta.days).capitalizingFirst + (delta.days > 0 ? " apart" : ""))
                    .font(Neka.display(24, weight: .bold))
                    .foregroundColor(Neka.ink)
                HStack(spacing: 8) {
                    if let t = delta.trend {
                        changePill("\(PhotoStats.signed(t)) lb trend", good: t <= 0)
                    } else if let s = delta.scale {
                        changePill("\(PhotoStats.signed(s)) lb", good: s <= 0)
                    }
                    if let f = delta.bodyFatPoints {
                        changePill("\(PhotoStats.signed(f))% body fat", good: f <= 0)
                    }
                }
                if delta.trend != nil, let s = delta.scale {
                    Text("\(PhotoStats.signed(s)) lb on the scale")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func changePill(_ text: String, good: Bool) -> some View {
        NekaPill(text: text, tint: good ? Neka.greenText : Neka.orangeText, fill: good ? Neka.greenSoft : Neka.orangeSoft)
    }

    // MARK: - Wipe

    private func wipe(before: ProgressPhotoEntry, after: ProgressPhotoEntry) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    let x = w * split
                    ZStack(alignment: .topLeading) {
                        photo(after)
                            .frame(width: w, height: geo.size.height)
                            .clipped()
                        photo(before)
                            .frame(width: w, height: geo.size.height)
                            .clipped()
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: max(0, x))
                            }
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: geo.size.height)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .offset(x: x - 1)
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white))
                            .shadow(color: .black.opacity(0.3), radius: 3)
                            .offset(x: x - 18, y: geo.size.height / 2 - 18)
                        caption(before, title: "Before")
                            .padding(8)
                            .opacity(split > 0.15 ? 1 : 0)
                        caption(after, title: "After")
                            .padding(8)
                            .frame(width: w, alignment: .trailing)
                            .opacity(split < 0.85 ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                split = min(1, max(0, value.location.x / max(1, w)))
                            }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before and after comparison")
            .accessibilityValue("\(Int(split * 100)) percent before")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: split = min(1, split + 0.1)
                case .decrement: split = max(0, split - 0.1)
                @unknown default: break
                }
            }
    }

    // MARK: - Overlay

    /// The newer photo with the older one as a ghost on top: line up the
    /// pose and the difference jumps out.
    private func overlay(before: ProgressPhotoEntry, after: ProgressPhotoEntry) -> some View {
        VStack(spacing: 10) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { photo(after) }
                .overlay { photo(before).opacity(ghost) }
                .overlay(alignment: .topLeading) { caption(before, title: "Before (ghost)").padding(8) }
                .overlay(alignment: .topTrailing) { caption(after, title: "After").padding(8) }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack(spacing: 10) {
                Text("After")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                Slider(value: $ghost, in: 0...1)
                    .tint(Neka.ink)
                    .accessibilityLabel("Before photo opacity")
                Text("Before")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
    }

    // MARK: - Side by side

    private func labeled(_ entry: ProgressPhotoEntry, title: String) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay { photo(entry) }
            .overlay(alignment: .topLeading) { caption(entry, title: title).padding(6) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Zoom

    /// Pinch zooms every photo on screen together.
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in pinch = value.magnification }
            .onEnded { value in
                zoom = min(4, max(1, zoom * value.magnification))
                pinch = 1
            }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func photo(_ entry: ProgressPhotoEntry) -> some View {
        if let image = store.image(for: entry) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(scale)
        } else {
            Rectangle().fill(Neka.track)
        }
    }

    private func caption(_ entry: ProgressPhotoEntry, title: String) -> some View {
        PhotoCaption(title: title, date: entry.date, stats: data.stats(for: entry))
    }

    // MARK: - Picking

    /// Thumbnails, oldest to newest: tap to set the Before or After photo.
    private var scrubber: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pick photos")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                Picker("Setting", selection: $picking) {
                    ForEach(Slot.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.entries) { e in
                            Button { pick(e) } label: { scrubberCell(e) }
                                .buttonStyle(.plain)
                                .id(e.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(afterID, anchor: .trailing) }
            }
        }
        .padding(12)
        .nekaCard()
    }

    private func scrubberCell(_ e: ProgressPhotoEntry) -> some View {
        let tag: String? = e.id == beforeID ? "B" : e.id == afterID ? "A" : nil
        return VStack(spacing: 3) {
            Group {
                if let image = store.thumbnail(for: e) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Neka.track)
                }
            }
            .frame(width: 52, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tag == nil ? Color.clear : Neka.ink, lineWidth: 2.5)
            )
            .overlay(alignment: .topTrailing) {
                if let tag {
                    Text(tag)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(Neka.onInk)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Neka.ink))
                        .offset(x: 4, y: -4)
                }
            }
            Text(e.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
        }
        .accessibilityLabel("Photo from \(e.date.formatted(date: .abbreviated, time: .omitted))\(tag == "B" ? ", before" : tag == "A" ? ", after" : "")")
    }

    private func pick(_ e: ProgressPhotoEntry) {
        withAnimation(.easeOut(duration: 0.2)) {
            if picking == .before { beforeID = e.id } else { afterID = e.id }
            // Keep Before older than After.
            if let b = before, let a = after, b.date > a.date {
                let older = afterID
                afterID = beforeID
                beforeID = older
            }
            picking = picking == .before ? .after : .before
        }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    // MARK: - Share

    private var shareRow: some View {
        VStack(spacing: 6) {
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview("My progress", image: shareImage)) {
                    Label("Share comparison", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
            }
            Text("Your photos stay on this iPhone. Sharing makes one labeled image, and only you choose where it goes.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @MainActor
    private func renderShareImage() {
        guard let before, let after, let delta,
              let a = store.image(for: before), let b = store.image(for: after) else {
            shareImage = nil
            return
        }
        let card = PhotoShareCard(before: a, after: b,
                                  beforeCaption: PhotoCaption(title: "Before", date: before.date, stats: data.stats(for: before)),
                                  afterCaption: PhotoCaption(title: "After", date: after.date, stats: data.stats(for: after)),
                                  summary: delta.summary)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        shareImage = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

// MARK: - Caption

/// Date, trend, scale and body fat on a dark chip over the photo.
struct PhotoCaption: View {
    let title: String
    let date: Date
    let stats: PhotoStats.Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
            Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.system(size: 11, weight: .semibold))
            if let t = stats.trend {
                Text("\(PhotoStats.pounds(t)) lb trend")
                    .font(.system(size: 11, weight: .medium))
            }
            if let s = stats.scale {
                Text("\(PhotoStats.pounds(s)) lb scale")
                    .font(.system(size: 10))
                    .opacity(0.85)
            }
            if let f = stats.bodyFat {
                Text("\(PhotoStats.percent(f)) body fat")
                    .font(.system(size: 10))
                    .opacity(0.85)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45)))
    }
}

// MARK: - Share card

/// The image Share sends: both photos labeled, the change, a small Dialed mark.
private struct PhotoShareCard: View {
    let before: UIImage
    let after: UIImage
    let beforeCaption: PhotoCaption
    let afterCaption: PhotoCaption
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                panel(before, beforeCaption)
                panel(after, afterCaption)
            }
            HStack(alignment: .center) {
                Text(summary)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    Text("Dialed")
                }
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(18)
        .frame(width: 720)
        .background(Color(red: 0.07, green: 0.08, blue: 0.09))
    }

    private func panel(_ image: UIImage, _ caption: PhotoCaption) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .overlay(alignment: .topLeading) { caption.padding(8) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + String(dropFirst()) }
}
