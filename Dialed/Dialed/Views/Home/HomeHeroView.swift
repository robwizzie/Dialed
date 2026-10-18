//
//  HomeHeroView.swift
//  Dialed
//
//  The signature Home hero: your photo, lifted off its background, softly
//  fading into the page, with live vitals pinned to your body by thin
//  leader lines — heart at the head, breathing at the neck, blood oxygen
//  at the shoulder, weight at the chest.
//

import SwiftUI

struct HomeHeroView: View {
    let image: UIImage?
    let isCutout: Bool
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

    private let height: CGFloat = 430

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                backdrop(w: w, h: h)
                photo(w: w, h: h)
                    .onTapGesture(perform: onTapPhoto)
                callouts(w: w, h: h)
                captionView
                    .frame(width: w * 0.42, alignment: .leading)
                    .position(x: 18 + w * 0.21, y: h - 44)
            }
            .clipShape(RoundedRectangle(cornerRadius: Neka.heroRadius, style: .continuous))
        }
        .frame(height: height)
    }

    // MARK: - Layers

    private func backdrop(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.95), Neka.paperDeep.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(Neka.greenSoft.opacity(0.8))
                .frame(width: w * 0.9)
                .blur(radius: 70)
                .offset(x: w * 0.25, y: -h * 0.15)
            Circle()
                .fill(Neka.orangeSoft.opacity(0.7))
                .frame(width: w * 0.6)
                .blur(radius: 70)
                .offset(x: -w * 0.3, y: h * 0.3)
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
                .saturation(0.92)
                .mask { fadeMask }
                .frame(width: w, height: h, alignment: .bottom)
                .offset(x: w * 0.08, y: photoOffsetY)
                .overlay {
                    if isProcessing {
                        ProgressView()
                            .tint(Neka.ink)
                            .padding(14)
                            .background(Circle().fill(.white.opacity(0.9)))
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
            .overlay(alignment: .center) {
                Button(action: onTapPhoto) {
                    Label("Add your photo", systemImage: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                .offset(x: w * 0.08, y: h * 0.12)
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

    // MARK: - Callouts

    private struct Callout {
        let title: String
        let value: String
        let unit: String
        let status: String
        /// Top-left of the label, as a fraction of the hero.
        let label: CGPoint
        /// Where the dot sits on the body.
        let dot: CGPoint
        let labelOnLeft: Bool
    }

    private var calloutModels: [Callout] {
        [
            Callout(
                title: "Heart",
                value: heartRate.map { "\(Int($0.rounded()))" } ?? "--",
                unit: "bpm",
                status: heartRate == nil ? "No data" : (heartRateIsLive ? "Live" : "Resting"),
                label: CGPoint(x: 0.05, y: 0.10),
                dot: CGPoint(x: 0.52, y: 0.22),
                labelOnLeft: true
            ),
            Callout(
                title: "Breathing",
                value: breathingRate.map { String(format: "%.0f", $0) } ?? "--",
                unit: "rpm",
                status: breathingRate.map { (12...20).contains($0) ? "Normal" : "Check" } ?? "No data",
                label: CGPoint(x: 0.68, y: 0.36),
                dot: CGPoint(x: 0.56, y: 0.47),
                labelOnLeft: false
            ),
            Callout(
                title: "Blood O₂",
                value: spO2.map { String(format: "%.0f", $0) } ?? "--",
                unit: "%",
                status: spO2.map { $0 >= 95 ? "Normal" : "Low" } ?? "No data",
                label: CGPoint(x: 0.05, y: 0.46),
                dot: CGPoint(x: 0.36, y: 0.60),
                labelOnLeft: true
            ),
            Callout(
                title: "Weight",
                value: weight.map { String(format: "%.1f", $0) } ?? "--",
                unit: "lb",
                status: weightNote ?? "Step on the scale",
                label: CGPoint(x: 0.68, y: 0.62),
                dot: CGPoint(x: 0.58, y: 0.74),
                labelOnLeft: false
            )
        ]
    }

    private func callouts(w: CGFloat, h: CGFloat) -> some View {
        let labelWidth: CGFloat = min(118, w * 0.3)
        return ZStack(alignment: .topLeading) {
            ForEach(calloutModels, id: \.title) { c in
                let labelOrigin = CGPoint(x: c.label.x * w, y: c.label.y * h)
                let dot = CGPoint(x: c.dot.x * w, y: c.dot.y * h)
                // Line runs from the end of the title row to the dot.
                let lineStart = c.labelOnLeft
                    ? CGPoint(x: labelOrigin.x + labelWidth * 0.62, y: labelOrigin.y + 8)
                    : CGPoint(x: labelOrigin.x - 6, y: labelOrigin.y + 8)

                Path { p in
                    p.move(to: lineStart)
                    p.addLine(to: dot)
                }
                .stroke(Neka.ink.opacity(0.25), lineWidth: 0.8)

                PulseDot()
                    .position(dot)

                calloutLabel(c)
                    .frame(width: labelWidth, alignment: .leading)
                    .position(x: labelOrigin.x + labelWidth / 2, y: labelOrigin.y + 30)
            }
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }

    private func calloutLabel(_ c: Callout) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(c.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.ink)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(c.value)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .contentTransition(.numericText())
                Text(c.unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.ink.opacity(0.8))
            }
            Text(c.status)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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

/// Yellow dot inside a frosted halo that breathes gently.
private struct PulseDot: View {
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                .scaleEffect(breathe ? 1.12 : 0.92)
            Circle()
                .fill(Neka.pulse)
                .frame(width: 9, height: 9)
                .shadow(color: Neka.pulse.opacity(0.8), radius: 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}
