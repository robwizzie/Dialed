//
//  DialedMark.swift
//  Dialed
//
//  The Dialed mark, drawn live — the same three shapes as the app icon
//  (Design/AppIcon/make_icon.py): a thick green → sky → lavender ring
//  with an Activity-ring shadow under its end cap, a smooth glass knob
//  with a quiet printed scale, and one pointer dot that turns with the
//  value. On iOS 26 the knob is real Liquid Glass.
//

import SwiftUI

struct DialedMark: View, Animatable {
    /// 0…1, how far the dial is turned. The icon sits at 0.74.
    var value: Double = 0.74

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    @Environment(\.colorScheme) private var scheme

    // Geometry in icon units (the icon is 1024 wide); scaled to fit.
    private static let start = 135.0
    private static let sweep = 270.0
    private static let ringRadius = 318.0
    private static let ringWidth = 104.0
    private static let knobRadius = 206.0
    private static let outer = ringRadius + ringWidth / 2

    /// Ring colour by position on the scale: green → sky → lavender by the
    /// icon's resting value, lavender after that.
    static let ringGradient = Gradient(stops: [
        .init(color: Neka.green, location: 0),
        .init(color: Neka.sky, location: 0.40 * sweep / 360),
        .init(color: Neka.lavender, location: 0.74 * sweep / 360),
        .init(color: Neka.lavender, location: sweep / 360)
    ])

    private var dark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let k = side / (2 * Self.outer)          // icon units → points
            let v = min(1, max(0, value))
            let angle = Self.start + Self.sweep * v
            let ring = Self.ringRadius * 2 * k

            ZStack {
                // Track for the rest of the scale.
                Circle()
                    .trim(from: 0, to: Self.sweep / 360)
                    .stroke((dark ? Color.white : .black).opacity(dark ? 0.10 : 0.06),
                            style: StrokeStyle(lineWidth: Self.ringWidth * k, lineCap: .round))
                    .rotationEffect(.degrees(Self.start))
                    .frame(width: ring, height: ring)

                // Shadow under the end cap, falling onto the track.
                Circle()
                    .fill(.black.opacity(dark ? 0.55 : 0.30))
                    .frame(width: (Self.ringWidth - 8) * k, height: (Self.ringWidth - 8) * k)
                    .blur(radius: 9 * k)
                    .offset(x: Self.ringRadius * k)
                    .rotationEffect(.degrees(angle + 2.5))
                    .opacity(v > 0.02 ? 1 : 0)

                // The coloured arc. The circle is rotated to `start`, so the
                // gradient is laid out from 0° in its own space.
                Circle()
                    .trim(from: 0, to: max(0.001, Self.sweep / 360 * v))
                    .stroke(AngularGradient(gradient: Self.ringGradient, center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: Self.ringWidth * k, lineCap: .round))
                    .rotationEffect(.degrees(Self.start))
                    .frame(width: ring, height: ring)

                knob(k: k, angle: angle)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func knob(k: CGFloat, angle: Double) -> some View {
        let d = Self.knobRadius * 2 * k
        let face = LinearGradient(
            colors: dark ? [Color(hex: "4A4A4F"), Color(hex: "2A2A2E")] : [.white, Color(hex: "F1F1F3")],
            startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1))

        return ZStack {
            Circle().fill(face).glassKnob()
            Circle().stroke((dark ? Color.white : .black).opacity(dark ? 0.10 : 0.05), lineWidth: 3 * k)
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                     startPoint: .top, endPoint: .center))
                .padding(4 * k)
                .opacity(dark ? 0.35 : 0.9)

            // The printed scale that makes it a dial.
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r0 = (Self.knobRadius - 30) * k, r1 = (Self.knobRadius - 14) * k
                for i in 0...9 {
                    let a = (Self.start + Self.sweep * Double(i) / 9) * .pi / 180
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                    p.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                    ctx.stroke(p, with: .color((dark ? Color.white : .black).opacity(dark ? 0.18 : 0.14)),
                               style: StrokeStyle(lineWidth: 9 * k, lineCap: .round))
                }
            }

            // Pointer dot, turning with the value.
            Circle()
                .fill(dark ? Color.white : Neka.ink)
                .frame(width: 52 * k, height: 52 * k)
                .offset(x: 146 * k)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: d, height: d)
        .background(
            Circle()
                .fill(.black.opacity(dark ? 0.60 : 0.20))
                .padding(6 * k)
                .blur(radius: 28 * k)
                .offset(y: 30 * k)
        )
    }
}

private extension View {
    /// Real Liquid Glass on iOS 26, the drawn face before that.
    @ViewBuilder
    func glassKnob() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self
        }
    }
}

/// Mark + "Dialed." wordmark, for headers.
struct DialedLockup: View {
    var markSize: CGFloat = 34
    var textSize: CGFloat = 26

    var body: some View {
        HStack(spacing: markSize * 0.3) {
            DialedMark()
                .frame(width: markSize, height: markSize)
            (Text("Dialed").foregroundColor(Neka.ink) + Text(".").foregroundColor(Neka.green))
                .font(Neka.display(textSize, weight: .bold))
                .tracking(-textSize * 0.03)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dialed")
    }
}

#Preview {
    VStack(spacing: 32) {
        DialedMark().frame(width: 220, height: 220)
        DialedLockup()
    }
    .padding()
    .background(Neka.paper)
}
