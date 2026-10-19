//
//  DialedMark.swift
//  Dialed
//
//  The Dialed mark, drawn live — the same glass dial as the app icon
//  (Design/AppIcon/make_icon.py):
//
//    • a full 270° scale ring in all four app colours, lit like a glass tube
//    • a graduated scale inside the ring, lit up to the value
//    • a raised knob in a socket — knurled side wall, chamfered edge and a
//      frosted, slightly dished glass top with a pointer groove
//    • a glass lens riding the ring at the value, tinted by the colour
//      under it
//
//  The glass is drawn (the same as the icon) rather than live system
//  glass, so it stays calm on the splash. `value` animates:
//  the lens slides along the ring and the pointer turns with it.
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
    private static let ringRadius = 316.0
    private static let ringWidth = 92.0
    private static let knobRadius = 200.0
    private static let lensRadius = 50.0
    private static let outer = ringRadius + lensRadius + 4

    static let ringGradient = DialPalette.ringGradient(span: sweep / 360)

    static func color(at t: Double) -> Color { DialPalette.color(at: t) }

    private var dark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let k = side / (2 * Self.outer)          // icon units → points
            let v = min(1, max(0, value))
            let angle = Self.start + Self.sweep * v

            ZStack {
                // Colour bloom behind everything, for the glass to pick up.
                ringShape(radius: Self.ringRadius - 40, width: 200, k: k)
                    .blur(radius: 60 * k)
                    .opacity(dark ? 0.45 : 0.35)

                ringShape(radius: Self.ringRadius, width: Self.ringWidth, k: k)
                ringLighting(k: k)

                scale(k: k, value: v)
                knob(k: k, angle: angle)

                lens(k: k, value: v)
                    .offset(x: Self.ringRadius * k)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - Ring

    private func ringShape(radius: Double, width: Double, k: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: Self.sweep / 360)
            .stroke(AngularGradient(gradient: Self.ringGradient, center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: width * k, lineCap: .round))
            .rotationEffect(.degrees(Self.start))
            .frame(width: radius * 2 * k, height: radius * 2 * k)
    }

    /// Light from the top left: a bright edge along the outside of the
    /// tube, a soft sheen down its middle, a faint shade on the inside edge.
    private func ringLighting(k: CGFloat) -> some View {
        let spec = Self.specular(strength: dark ? 0.55 : 1)
        let r = Self.ringRadius, w = Self.ringWidth
        let pad = 3.0 / 360, end = Self.sweep / 360
        let edge = r + w / 2 - 9, mid = r - 6, inner = r - w / 2 + 6
        return ZStack {
            Circle().trim(from: pad, to: end - pad)
                .stroke(spec, style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
                .rotationEffect(.degrees(Self.start))
                .frame(width: edge * 2 * k, height: edge * 2 * k)
            Circle().trim(from: 16.0 / 360, to: end - 16.0 / 360)
                .stroke(.white.opacity(dark ? 0.12 : 0.22), style: StrokeStyle(lineWidth: 26 * k, lineCap: .round))
                .blur(radius: 8 * k)
                .rotationEffect(.degrees(Self.start))
                .frame(width: mid * 2 * k, height: mid * 2 * k)
            Circle().trim(from: pad, to: end - pad)
                .stroke(.black.opacity(0.08), style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
                .rotationEffect(.degrees(Self.start))
                .frame(width: inner * 2 * k, height: inner * 2 * k)
        }
    }

    // MARK: - Scale

    /// Graduations printed between the knob and the ring, lit in the
    /// ring's colours up to the value.
    private func scale(k: CGFloat, value v: Double) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let n = 27
            for i in 0...n {
                let f = Double(i) / Double(n)
                let a = (Self.start + Self.sweep * f) * .pi / 180
                let major = i % 3 == 0
                let r0 = (major ? 220.0 : 229.0) * k, r1 = 250.0 * k
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                p.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                let lit = f <= v + 1e-6
                let color = lit ? Self.color(at: f) : (dark ? Color.white : .black).opacity(dark ? 0.22 : 0.16)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: (major ? 11 : 7) * k, lineCap: .round))
            }
        }
    }

    // MARK: - Knob

    /// A real knob seen from just above: it sits in a recessed socket,
    /// rises on a knurled side wall, and has a slightly dished glass top
    /// with a chamfered edge.
    private static let lift = 16.0, wall = 30.0

    private func knob(k: CGFloat, angle: Double) -> some View {
        let r = Self.knobRadius
        let d = r * 2 * k
        return ZStack {
            // Socket the knob sits in.
            Circle()
                .fill(LinearGradient(stops: [.init(color: .black.opacity(dark ? 0.65 : 0.22), location: 0),
                                             .init(color: .black.opacity(0), location: 0.55),
                                             .init(color: .white.opacity(dark ? 0.38 : 0.7), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: (r + 14) * 2 * k, height: (r + 14) * 2 * k)

            // Cast shadow, long and soft, falling down and away from the light.
            Ellipse()
                .fill(.black.opacity(dark ? 0.85 : 0.29))
                .frame(width: (r + 4) * 2 * k, height: (r - 10) * 2 * k)
                .blur(radius: 24 * k)
                .offset(x: 14 * k, y: (Self.wall - Self.lift + 34) * k)
            Circle()
                .fill(.black.opacity(dark ? 0.75 : 0.25))
                .frame(width: (r + 2) * 2 * k, height: (r + 2) * 2 * k)
                .blur(radius: 8 * k)
                .offset(y: (Self.wall - Self.lift + 6) * k)

            sideWall(k: k)
                .frame(width: d, height: d + Self.wall * k)
                .offset(y: (Self.wall / 2 - Self.lift) * k)

            top(k: k, angle: angle)
                .frame(width: d, height: d)
                .offset(y: -Self.lift * k)
        }
    }

    /// The cylinder between the top face and the base, with vertical
    /// knurling spaced by its curve.
    private func sideWall(k: CGFloat) -> some View {
        Canvas { ctx, size in
            let r = Self.knobRadius * k, h = Self.wall * k
            let cx = size.width / 2, top = r
            var body = Path()
            body.addArc(center: CGPoint(x: cx, y: top), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            body.addLine(to: CGPoint(x: cx + r, y: top + h))
            body.addArc(center: CGPoint(x: cx, y: top + h), radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            body.closeSubpath()
            let edge = dark ? Color(hex: "1A1A1E") : Color(hex: "BDBDC6")
            let mid = dark ? Color(hex: "5A5A62") : Color(hex: "F4F4F7")
            ctx.fill(body, with: .linearGradient(
                Gradient(stops: [.init(color: edge, location: 0), .init(color: mid, location: 0.3),
                                 .init(color: mid, location: 0.65), .init(color: edge, location: 1)]),
                startPoint: CGPoint(x: cx - r, y: 0), endPoint: CGPoint(x: cx + r, y: 0)))
            for i in 1..<60 {
                let x = cx - r * cos(Double(i) / 60 * .pi)
                let y = top + sqrt(max(0, r * r - (x - cx) * (x - cx)))
                var p = Path()
                p.move(to: CGPoint(x: x, y: y - 2 * k))
                p.addLine(to: CGPoint(x: x, y: y + h - 3 * k))
                ctx.stroke(p, with: .color(.black.opacity(dark ? 0.45 : 0.16)),
                           style: StrokeStyle(lineWidth: 3.5 * k, lineCap: .round))
            }
        }
    }

    private func top(k: CGFloat, angle: Double) -> some View {
        let r = Self.knobRadius
        let glassA = dark ? 0.14 : 0.62
        let dishA = dark ? 0.30 : 0.10
        return ZStack {
            Circle().fill(dark ? Color(hex: "202024") : .white)
            // Frosted: the colours round the knob, blurred and pulled inward.
            ringShape(radius: r - 10, width: 90, k: k)
                .blur(radius: 34 * k)
                .opacity(0.9)
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(min(1, glassA + 0.25)), .white.opacity(glassA)],
                                     startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)))
            // Slight dish in the top.
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white.opacity(dark ? 0.19 : 0.35), location: 0),
                                             .init(color: .white.opacity(0), location: 0.7),
                                             .init(color: .black.opacity(dishA), location: 1)],
                                     center: UnitPoint(x: 0.62, y: 0.70), startRadius: 0, endRadius: (r - 22) * 1.5 * k))
                .padding(22 * k)
            // Chamfered edge: light catches the near lip, the far lip is shaded.
            Circle()
                .stroke(LinearGradient(stops: [.init(color: .black.opacity(dishA * 1.4), location: 0),
                                               .init(color: .black.opacity(0), location: 0.5),
                                               .init(color: .white.opacity(dark ? 0.5 : 0.9), location: 1)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 20 * k)
                .padding(11 * k)
            Circle()
                .stroke(Self.specular(strength: dark ? 0.55 : 1), lineWidth: 4 * k)
                .padding(1.5 * k)

            // Pointer: a groove cut into the top, turning with the value.
            if !dark {
                Capsule().fill(.white.opacity(0.85))
                    .frame(width: 116 * k, height: 26 * k)
                    .offset(x: 109 * k)
                    .rotationEffect(.degrees(angle))
                    .offset(y: 3 * k)
            }
            Capsule().fill(dark ? Color.white : Neka.ink)
                .frame(width: 116 * k, height: 26 * k)
                .offset(x: 109 * k)
                .rotationEffect(.degrees(angle))
        }
        .clipShape(Circle())
    }

    // MARK: - Lens

    private func lens(k: CGFloat, value v: Double) -> some View {
        let d = Self.lensRadius * 2 * k
        let tint = Self.color(at: v)
        return ZStack {
            Circle().fill(tint)
            Circle().fill(RadialGradient(
                stops: [.init(color: .white.opacity(0.55), location: 0),
                        .init(color: .white.opacity(0.12), location: 0.6),
                        .init(color: .white.opacity(0.05), location: 1)],
                center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.8))
            Circle()
                .stroke(Self.specular(strength: dark ? 0.55 : 1), lineWidth: 6 * k)
                .padding(3 * k)
            Ellipse()
                .fill(.white.opacity(dark ? 0.5 : 0.85))
                .frame(width: 38 * k, height: 18 * k)
                .rotationEffect(.degrees(-30))
                .offset(x: -16 * k, y: -21 * k)
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(dark ? 0.45 : 0.2), radius: 8 * k, y: 14 * k)
    }

    /// White edge light: bright top left, gone across the middle, softer
    /// again bottom right.
    private static func specular(strength s: Double) -> LinearGradient {
        LinearGradient(stops: [.init(color: .white.opacity(0.95 * s), location: 0),
                               .init(color: .white.opacity(0), location: 0.45),
                               .init(color: .white.opacity(0), location: 0.8),
                               .init(color: .white.opacity(0.55 * s), location: 1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
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
                .motionTilt(6)
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
