//
//  HomeHeroView.swift
//  Dialed
//
//  The signature Home hero: your photo, lifted off its background, softly
//  fading into the page, with live vitals on frosted plates pinned to your
//  body by thin leader lines — heart at the head, breathing at the neck,
//  blood oxygen at the shoulder, weight at the chest.
//
//  With a mood avatar on, the illustration fills the hero, framed on the
//  face, and the four vitals sit in a row of tiles along the bottom so
//  nothing covers the face.
//

import SwiftUI

struct HomeHeroView: View {
    let image: UIImage?
    let isCutout: Bool
    /// `image` is a full-scene mood avatar rather than your photo.
    var isAvatar: Bool = false
    let isProcessing: Bool
    var photoScale: Double = 1
    var photoOffsetY: Double = 0

    let heartRate: Double?
    let heartRateIsLive: Bool
    let breathingRate: Double?
    let spO2: Double?
    let weight: Double?
    let weightNote: String?
    let caption: String

    var onTapPhoto: () -> Void

    /// Today's mood chip (top-right) — opens the avatar sheet.
    var mood: AvatarMood? = nil
    var moodScore: Int? = nil
    var onTapMood: () -> Void = {}

    private let height: CGFloat = 430
    @ObservedObject private var studio = AvatarStudio.shared

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                if isAvatar, let image {
                    avatarLayer(image, w: w, h: h)
                        .onTapGesture(perform: onTapPhoto)
                    vitalTiles
                        .frame(width: w, height: h, alignment: .bottom)
                    // Avatar level (top-left), or a "leveled up" call-out.
                    Group {
                        if studio.levelUp != nil {
                            Button(action: onTapMood) {
                                Label("Leveled up!", systemImage: "arrow.up.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(LinearGradient(colors: [Neka.amber, Neka.orange],
                                                                              startPoint: .leading, endPoint: .trailing)))
                            }
                            .buttonStyle(.dialedScale)
                        } else if let evolution = studio.evolution {
                            AvatarStageBadge(reading: evolution)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                } else {
                    backdrop(w: w, h: h)
                    photo(w: w, h: h)
                        .onTapGesture(perform: onTapPhoto)
                    callouts(w: w, h: h)
                    captionView
                        .frame(width: w * 0.42, alignment: .leading)
                        .position(x: 18 + w * 0.21, y: h - 44)
                }
                if image != nil, let mood {
                    moodChip(mood)
                        .frame(width: w - 16, alignment: .trailing)
                        .padding(.top, 16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Neka.heroRadius, style: .continuous))
        }
        .frame(height: height)
    }

    private func moodChip(_ mood: AvatarMood) -> some View {
        Button(action: onTapMood) {
            HStack(spacing: 6) {
                Text(mood.emoji)
                Text(mood.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                if let moodScore {
                    Text("\(moodScore)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: mood.accentHex))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Neka.surface.opacity(0.92)))
            .overlay(Capsule().stroke(Color(hex: mood.accentHex).opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("Today's mood: \(mood.title)\(moodScore.map { ", \($0) of 100" } ?? ""). Opens your avatar.")
    }

    // MARK: - Layers

    private func backdrop(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Neka.surface.opacity(0.95), Neka.paperDeep.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
            // Radial gradients instead of blurred circles: same soft glow,
            // no per-frame Gaussian blur.
            RadialGradient(
                colors: [Neka.greenSoft, Neka.greenSoft.opacity(0)],
                center: UnitPoint(x: 0.78, y: 0.25), startRadius: 0, endRadius: w * 0.6
            )
            RadialGradient(
                colors: [Neka.orangeSoft.opacity(0.9), Neka.orangeSoft.opacity(0)],
                center: UnitPoint(x: 0.15, y: 0.8), startRadius: 0, endRadius: w * 0.5
            )
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func photo(w: CGFloat, h: CGFloat) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: w * 0.86 * photoScale, height: h * 0.95 * photoScale, alignment: .bottom)
                .mask { fadeMask }
                .frame(width: w, height: h, alignment: .bottom)
                .offset(x: w * 0.08, y: photoOffsetY)
                .overlay {
                    if isProcessing {
                        ProgressView()
                            .tint(Neka.ink)
                            .padding(14)
                            .background(Circle().fill(Neka.surface.opacity(0.9)))
                    }
                }
                .accessibilityLabel("Your photo. Tap to change.")
        } else {
            VStack(spacing: 14) {
                Image(systemName: "person.fill")
                    .font(.system(size: 220, weight: .regular))
                    .foregroundStyle(LinearGradient(
                        colors: [Neka.paperDeep, Neka.paperDeep.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
            .frame(width: w, height: h, alignment: .bottom)
            .offset(x: w * 0.08, y: 30)
            // Top-trailing keeps it clear of the four callouts.
            .overlay(alignment: .topTrailing) {
                Button(action: onTapPhoto) {
                    Label("Add your photo", systemImage: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                .padding(16)
            }
        }
    }

    /// Cutouts fade out at the bottom; full photos also vignette at the
    /// edges so the background melts into the page.
    @ViewBuilder
    private var fadeMask: some View {
        if isCutout {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.62),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            RadialGradient(
                stops: [
                    .init(color: .black, location: 0.35),
                    .init(color: .clear, location: 0.72)
                ],
                center: .center, startRadius: 0, endRadius: 260
            )
        }
    }

    // MARK: - Avatar layout

    private func avatarLayer(_ image: UIImage, w: CGFloat, h: CGFloat) -> some View {
        // Face lands in the upper third, clear of the tiles at the bottom.
        FocusedImage(image: image, anchorY: 0.34)
            .frame(width: w, height: h)
            .overlay(alignment: .bottom) {
                // Darkens the scene behind the tiles so they always read.
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: h * 0.4)
                .allowsHitTesting(false)
            }
            .accessibilityLabel("Your avatar for today. Tap to open.")
    }

    private struct Vital: Identifiable {
        let title: String
        let icon: String
        let tint: Color
        let value: String
        let unit: String
        let status: String
        let hasData: Bool
        var id: String { title }
    }

    private var vitals: [Vital] {
        [
            Vital(title: "Heart", icon: "heart.fill", tint: Neka.orange,
                  value: heartRate.map { "\(Int($0.rounded()))" } ?? "--", unit: "bpm",
                  status: heartRate == nil ? "No data" : (heartRateIsLive ? "Live" : "Resting"),
                  hasData: heartRate != nil),
            Vital(title: "Breathing", icon: "lungs.fill", tint: Neka.sky,
                  value: breathingRate.map { String(format: "%.0f", $0) } ?? "--", unit: "rpm",
                  status: breathingRate.map { (12...20).contains($0) ? "Normal" : "Check" } ?? "No data",
                  hasData: breathingRate != nil),
            Vital(title: "Blood O₂", icon: "drop.fill", tint: Neka.lavender,
                  value: spO2.map { String(format: "%.0f", $0) } ?? "--", unit: "%",
                  status: spO2.map { $0 >= 95 ? "Normal" : "Low" } ?? "No data",
                  hasData: spO2 != nil),
            Vital(title: "Weight", icon: "scalemass.fill", tint: Neka.green,
                  value: weight.map { String(format: "%.1f", $0) } ?? "--", unit: "lb",
                  status: weight == nil ? "Weigh in" : (weightNote ?? ""),
                  hasData: weight != nil)
        ]
    }

    private var vitalTiles: some View {
        HStack(spacing: 6) {
            ForEach(vitals) { v in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: v.icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(v.tint)
                        Text(v.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Neka.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(v.value)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(v.hasData ? Neka.ink : Neka.inkTertiary)
                            .contentTransition(.numericText())
                        Text(v.unit)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Text(v.status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(v.hasData ? Neka.inkSecondary : Neka.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Neka.hairline, lineWidth: 0.5)
                )
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    // MARK: - Callouts

    private struct Callout {
        let title: String
        let icon: String
        let tint: Color
        let value: String
        let unit: String
        let status: String
        let hasData: Bool
        /// Top of the plate, as a fraction of the hero's height. Plates sit
        /// against the left or right edge so they never float mid-photo.
        let top: CGFloat
        /// Where the dot sits on the body.
        let dot: CGPoint
        let labelOnLeft: Bool
    }

    private var calloutModels: [Callout] {
        [
            Callout(
                title: "Heart", icon: "heart.fill", tint: Neka.orange,
                value: heartRate.map { "\(Int($0.rounded()))" } ?? "--",
                unit: "bpm",
                status: heartRate == nil ? "No data" : (heartRateIsLive ? "Live" : "Resting"),
                hasData: heartRate != nil,
                top: 0.12,
                dot: CGPoint(x: 0.52, y: 0.22),
                labelOnLeft: true
            ),
            Callout(
                title: "Breathing", icon: "lungs.fill", tint: Neka.sky,
                value: breathingRate.map { String(format: "%.0f", $0) } ?? "--",
                unit: "rpm",
                status: breathingRate.map { (12...20).contains($0) ? "Normal" : "Check" } ?? "No data",
                hasData: breathingRate != nil,
                top: 0.34,
                dot: CGPoint(x: 0.56, y: 0.47),
                labelOnLeft: false
            ),
            Callout(
                title: "Blood O₂", icon: "drop.fill", tint: Neka.lavender,
                value: spO2.map { String(format: "%.0f", $0) } ?? "--",
                unit: "%",
                status: spO2.map { $0 >= 95 ? "Normal" : "Low" } ?? "No data",
                hasData: spO2 != nil,
                top: 0.44,
                dot: CGPoint(x: 0.36, y: 0.60),
                labelOnLeft: true
            ),
            Callout(
                title: "Weight", icon: "scalemass.fill", tint: Neka.green,
                value: weight.map { String(format: "%.1f", $0) } ?? "--",
                unit: "lb",
                status: weightNote ?? "Weigh in",
                hasData: weight != nil,
                top: 0.60,
                dot: CGPoint(x: 0.58, y: 0.74),
                labelOnLeft: false
            )
        ]
    }

    private func callouts(w: CGFloat, h: CGFloat) -> some View {
        let plateWidth: CGFloat = min(112, w * 0.31)
        let plateHeight: CGFloat = 70
        let inset: CGFloat = 12
        return ZStack(alignment: .topLeading) {
            ForEach(calloutModels, id: \.title) { c in
                let plateX = c.labelOnLeft ? inset : w - inset - plateWidth
                let plateY = c.top * h
                let dot = CGPoint(x: c.dot.x * w, y: c.dot.y * h)
                // Line runs from the plate's inner edge to the dot.
                let lineStart = CGPoint(x: c.labelOnLeft ? plateX + plateWidth : plateX, y: plateY + plateHeight / 2)

                // Light halo under a dark core: visible on the backdrop and on
                // dark clothing alike.
                let leader = Path { p in
                    p.move(to: lineStart)
                    p.addLine(to: dot)
                }
                leader.stroke(Neka.surface.opacity(0.7), lineWidth: 2.4)
                leader.stroke(Neka.ink.opacity(0.4), lineWidth: 0.9)

                PulseDot()
                    .position(dot)

                calloutLabel(c)
                    .frame(width: plateWidth, height: plateHeight)
                    .position(x: plateX + plateWidth / 2, y: plateY + plateHeight / 2)
            }
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }

    /// A frosted plate so the reading stays legible over any photo.
    private func calloutLabel(_ c: Callout) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: c.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(c.tint)
                Text(c.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(c.value)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(c.hasData ? Neka.ink : Neka.inkTertiary)
                    .contentTransition(.numericText())
                Text(c.unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(c.status)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Neka.shadow, radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Neka.cardStroke, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    private var captionView: some View {
        Text(caption)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(Neka.inkSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Yellow dot inside a frosted halo. Static on purpose: four looping
/// animations here kept the whole hero redrawing every frame.
private struct PulseDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Neka.surface.opacity(0.45))
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Neka.surface.opacity(0.9), lineWidth: 1))
            Circle()
                .fill(Neka.pulse)
                .frame(width: 9, height: 9)
        }
    }
}
