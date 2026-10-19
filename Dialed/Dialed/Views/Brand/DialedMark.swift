//
//  DialedMark.swift
//  Dialed
//
//  The Dialed mark, drawn live: a 270° scale of tick marks, the app's
//  green → sky → lavender → orange progress arc, a knurled glass knob
//  whose pointer turns with the value, and a bead riding the arc's end.
//  Same geometry as the app icon (Design/AppIcon/make_icon.py), so the
//  splash, headers and icon all match. On iOS 26 the knob is real
//  Liquid Glass; earlier versions get a drawn glass look.
//

import SwiftUI

struct DialedMark: View, Animatable {
    /// 0…1, how far the dial is turned.
    var value: Double = 0.74
    var showsTicks = true

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    @Environment(\.colorScheme) private var scheme

    // Geometry in icon units (the icon is 1024 wide); scaled to fit.
    private static let start = 135.0
    private static let sweep = 270.0
    private static let outer = 452.0

    static let palette: [(Double, (Double, Double, Double))] = [
        (0.00, (0x4C, 0xB8, 0x68)),   // green
        (0.38, (0x5D, 0xB4, 0xF0)),   // sky
        (0.70, (0xA8, 0x8B, 0xEB)),   // lavender
        (1.00, (0xF5, 0x9A, 0x4C))    // orange
    ]

    static let arcGradient = Gradient(stops: palette.map { stop -> Gradient.Stop in
        Gradient.Stop(color: color(at: stop.0), location: stop.0 * sweep / 360)
    })

    static func color(at t: Double) -> Color {
        let t = min(1, max(0, t))
        for (a, b) in zip(palette, palette.dropFirst()) where t <= b.0 {
            let f = (t - a.0) / (b.0 - a.0)
            return Color(red: (a.1.0 + (b.1.0 - a.1.0) * f) / 255,
                         green: (a.1.1 + (b.1.1 - a.1.1) * f) / 255,
                         blue: (a.1.2 + (b.1.2 - a.1.2) * f) / 255)
        }
        return Neka.orange
    }

    private var dark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let k = side / (2 * Self.outer)          // icon units → points
            let v = min(1, max(0, value))
            let pointer = Self.start + Self.sweep * v

            ZStack {
                if showsTicks { ticks(k: k, value: v) }

                // Track, then the coloured arc (conic gradient follows the arc).
                Circle()
                    .trim(from: 0, to: Self.sweep / 360)
                    .stroke((dark ? Color.white : Neka.ink).opacity(dark ? 0.08 : 0.07),
                            style: StrokeStyle(lineWidth: 60 * k, lineCap: .round))
                    .rotationEffect(.degrees(Self.start))
                    .frame(width: 624 * k, height: 624 * k)
                Circle()
                    .trim(from: 0, to: max(0.001, Self.sweep / 360 * v))
                    .stroke(AngularGradient(
                                gradient: Self.arcGradient,
                                center: .center,
                                // The circle is rotated to `start` below, so the
                                // gradient is laid out from 0° in its own space.
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 60 * k, lineCap: .round))
                    .rotationEffect(.degrees(Self.start))
                    .frame(width: 624 * k, height: 624 * k)
                    .shadow(color: Self.color(at: v).opacity(0.35), radius: 14 * k)

                knob(k: k, pointer: pointer)

                // Bead riding the end of the arc.
                Circle()
                    .fill(dark ? Color(hex: "151619") : .white)
                    .overlay(Circle().stroke(dark ? Color(hex: "F2F2F3") : Neka.ink, lineWidth: 12 * k))
                    .frame(width: 70 * k, height: 70 * k)
                    .offset(x: 312 * k)
                    .rotationEffect(.degrees(pointer))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - Pieces

    private func ticks(k: CGFloat, value v: Double) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let n = 18
            for i in 0...n {
                let f = Double(i) / Double(n)
                let a = (Self.start + Self.sweep * f) * .pi / 180
                let major = i % 3 == 0
                let r0 = (major ? 400.0 : 412.0) * k, r1 = (major ? 446.0 : 438.0) * k
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                p.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                let lit = f <= v + 0.0001
                let color: Color = lit ? Self.color(at: f) : (dark ? .white : Neka.ink).opacity(dark ? 0.34 : 0.30)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: (major ? 13 : 9) * k, lineCap: .round))
            }
        }
    }

    private func knob(k: CGFloat, pointer: Double) -> some View {
        let body = RadialGradient(
            colors: dark ? [Color(hex: "3A3B42"), Color(hex: "17181C")] : [.white, Color(hex: "E9E7E1")],
            center: UnitPoint(x: 0.38, y: 0.30), startRadius: 0, endRadius: 360 * k)
        let rim = LinearGradient(
            colors: [.white.opacity(dark ? 0.30 : 0.95), .white.opacity(0.05), .white.opacity(dark ? 0.15 : 0.45)],
            startPoint: .top, endPoint: .bottom)

        return ZStack {
            Circle().fill(body)
                .glassKnob()
            // Knurled grip round the edge.
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<96 {
                    let a = Double(i) / 96 * 2 * .pi
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + cos(a) * 186 * k, y: c.y + sin(a) * 186 * k))
                    p.addLine(to: CGPoint(x: c.x + cos(a) * 210 * k, y: c.y + sin(a) * 210 * k))
                    ctx.stroke(p, with: .color((dark ? Color.white : Neka.ink).opacity(0.10)),
                               style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
                }
            }
            Circle().fill(body).frame(width: 352 * k, height: 352 * k)
            Circle().stroke(rim, lineWidth: 5 * k).frame(width: 352 * k, height: 352 * k)
            Circle().stroke(rim, lineWidth: 7 * k)
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)], center: .center, startRadius: 0, endRadius: 112 * k))
                .frame(width: 224 * k, height: 124 * k)
                .rotationEffect(.degrees(-28))
                .offset(x: -62 * k, y: -92 * k)
                .opacity(dark ? 0.22 : 0.55)
            // Pointer, turning with the value.
            Capsule()
                .fill(dark ? Color(hex: "F2F2F3") : Neka.ink)
                .frame(width: 88 * k, height: 30 * k)
                .offset(x: 106 * k)
                .rotationEffect(.degrees(pointer))
        }
        .frame(width: 432 * k, height: 432 * k)
        .shadow(color: .black.opacity(dark ? 0.55 : 0.18), radius: 26 * k, y: 30 * k)
    }
}

private extension View {
    /// Real Liquid Glass on iOS 26, drawn glass before that.
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
