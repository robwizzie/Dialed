//
//  DialedMark.swift
//  Dialed
//
//  The Dialed mark, drawn live — the same glass dial as the app icon
//  (Design/AppIcon/make_icon.py):
//
//    • a full 270° scale ring in all four app colours, lit like a glass tube
//    • a frosted glass knob that picks up the colours round it, with one
//      pointer dot
//    • a glass lens riding the ring at the value, tinted by the colour
//      under it
//
//  On iOS 26 the knob and lens are real Liquid Glass. `value` animates:
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
    private static let lensRadius = 70.0
    private static let outer = ringRadius + lensRadius + 4

    /// green → sky → lavender → orange, sampled in OKLCH (make_icon.py) so
    /// the blends stay vivid instead of going grey.
    private static let rampHex: [UInt32] = [0x4CB868, 0x00BE9A, 0x00BEC3, 0x26BAE1, 0x61B2F2, 0x7AA6F7,
                                            0x9298F5, 0xA88BEB, 0xDD81C5, 0xF8848A, 0xF59A4C]
    private static func rgb(_ h: UInt32) -> (Double, Double, Double) {
        (Double(h >> 16 & 0xFF) / 255, Double(h >> 8 & 0xFF) / 255, Double(h & 0xFF) / 255)
    }
    static let ramp: [Color] = rampHex.map { let c = rgb($0); return Color(red: c.0, green: c.1, blue: c.2) }

    /// The ramp laid along the ring. The circle is rotated to `start`, so
    /// 0…0.75 is the scale and the gap is split between the two end
    /// colours — that keeps the round start cap green, not orange.
    static let ringGradient: Gradient = {
        let span = sweep / 360
        var stops = ramp.enumerated().map { i, c in
            Gradient.Stop(color: c, location: span * Double(i) / Double(ramp.count - 1))
        }
        stops.append(.init(color: ramp.last!, location: span + (1 - span) / 2))
        stops.append(.init(color: ramp.first!, location: span + (1 - span) / 2 + 0.0001))
        stops.append(.init(color: ramp.first!, location: 1))
        return Gradient(stops: stops)
    }()

    /// Colour on the ring at 0…1. A straight blend between ramp samples,
    /// which are close enough together to stay on the OKLCH path.
    static func color(at t: Double) -> Color {
        let x = min(1, max(0, t)) * Double(rampHex.count - 1)
        let i = min(rampHex.count - 2, Int(x)), f = x - Double(i)
        let a = rgb(rampHex[i]), b = rgb(rampHex[i + 1])
        return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
    }

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

    // MARK: - Knob

    private func knob(k: CGFloat, angle: Double) -> some View {
        let d = Self.knobRadius * 2 * k
        let glassA = dark ? 0.14 : 0.62
        return ZStack {
            // Frosted: the colours round the knob, blurred and pulled inward.
            ringShape(radius: Self.knobRadius - 10, width: 90, k: k)
                .blur(radius: 34 * k)
                .opacity(0.9)
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(min(1, glassA + 0.25)), .white.opacity(glassA)],
                                     startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)))
            Circle().stroke(.black.opacity(dark ? 0.12 : 0.05), lineWidth: 1.5 * k)
            Circle()
                .stroke(Self.specular(strength: dark ? 0.55 : 1), lineWidth: 7 * k)
                .padding(4 * k)

            // Pointer dot, turning with the value.
            Circle()
                .fill(dark ? Color.white : Neka.ink)
                .frame(width: 48 * k, height: 48 * k)
                .shadow(color: .black.opacity(0.18), radius: 8 * k, y: 4 * k)
                .offset(x: 140 * k)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .liquidGlass(tint: nil)
        .background(
            Circle()
                .fill(.black.opacity(dark ? 0.55 : 0.18))
                .padding(8 * k)
                .blur(radius: 24 * k)
                .offset(y: 28 * k)
        )
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
                .frame(width: 52 * k, height: 26 * k)
                .rotationEffect(.degrees(-30))
                .offset(x: -22 * k, y: -30 * k)
        }
        .frame(width: d, height: d)
        .liquidGlass(tint: tint)
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

private extension View {
    /// Real Liquid Glass on iOS 26, the drawn glass before that.
    @ViewBuilder
    func liquidGlass(tint: Color?) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = tint.map { Glass.regular.tint($0.opacity(0.5)) } ?? Glass.regular
            self.glassEffect(glass, in: Circle())
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
