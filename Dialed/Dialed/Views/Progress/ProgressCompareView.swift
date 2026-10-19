//
//  ProgressCompareView.swift
//  Dialed
//
//  Two progress photos, side by side or as a before/after wipe you drag
//  across. Each is labeled with its date and weight; pick any two.
//

import SwiftUI

struct ProgressCompareView: View {
    @ObservedObject private var store = ProgressPhotoStore.shared
    @State private var beforeID: UUID
    @State private var afterID: UUID
    @State private var mode: Mode = .wipe
    @State private var split: CGFloat = 0.5

    enum Mode: String, CaseIterable, Identifiable {
        case wipe, sideBySide
        var id: String { rawValue }
        var title: String { self == .wipe ? "Slider" : "Side by side" }
    }

    init(before: ProgressPhotoEntry, after: ProgressPhotoEntry) {
        _beforeID = State(initialValue: before.id)
        _afterID = State(initialValue: after.id)
    }

    private var before: ProgressPhotoEntry? { store.index.entry(id: beforeID) }
    private var after: ProgressPhotoEntry? { store.index.entry(id: afterID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.title).tag(m) }
                }
                .pickerStyle(.segmented)

                if let before, let after {
                    if mode == .wipe {
                        wipe(before: before, after: after)
                    } else {
                        HStack(spacing: 8) {
                            labeled(before, title: "Before")
                            labeled(after, title: "After")
                        }
                    }
                } else {
                    Text("Pick two photos to compare.")
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkTertiary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }

                HStack(spacing: 10) {
                    photoMenu(title: "Before", selection: $beforeID)
                    photoMenu(title: "After", selection: $afterID)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let before, let after {
                let days = Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0
                Text(days >= 7 ? "\(days / 7) week\(days / 7 == 1 ? "" : "s") apart" : "\(abs(days)) day\(abs(days) == 1 ? "" : "s") apart")
                    .font(Neka.display(24, weight: .bold))
                    .foregroundColor(Neka.ink)
                if let change = ProgressPhotoIndex.weightChange(from: before, to: after) {
                    Text("\(StrengthProgression.signed(change)) lb on the scale")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(change <= 0 ? Neka.green : Neka.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Side by side

    private func labeled(_ entry: ProgressPhotoEntry, title: String) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay { photo(entry) }
            .overlay(alignment: .topLeading) { caption(entry, title: title).padding(6) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Pieces

    @ViewBuilder
    private func photo(_ entry: ProgressPhotoEntry) -> some View {
        if let image = store.image(for: entry) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(Neka.track)
        }
    }

    private func caption(_ entry: ProgressPhotoEntry, title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.system(size: 11, weight: .semibold))
            if let w = entry.weightLbs {
                Text("\(String(format: "%.1f", w)) lb")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45)))
    }

    private func photoMenu(title: String, selection: Binding<UUID>) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(store.entries.reversed()) { e in
                    Text(menuLabel(e)).tag(e.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
                HStack {
                    Text(store.index.entry(id: selection.wrappedValue).map(menuLabel) ?? "Pick a photo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nekaCard()
        }
    }

    private func menuLabel(_ e: ProgressPhotoEntry) -> String {
        var s = e.date.formatted(.dateTime.month(.abbreviated).day().year())
        if let w = e.weightLbs { s += " · " + String(format: "%.1f lb", w) }
        return s
    }
}
