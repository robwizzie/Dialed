//
//  DialGauge.swift
//  Dialed (app + widgets)
//
//  The Dialed dial as a gauge: the same ring, scale and knob as the app
//  icon, drawn flat enough for widgets and small cards. Shared by the
//  Home "Dialed today" card and the Home Screen widget, so the icon, the
//  app and the widget all read the same way.
//

import SwiftUI

/// The icon's colours: green → sky → lavender → orange, sampled in OKLCH
/// (Design/AppIcon/make_icon.py) so the blends stay vivid.
enum DialPalette {
    static let rampHex: [UInt32] = [0x4CB868, 0x00BE9A, 0x00BEC3, 0x26BAE1, 0x61B2F2, 0x7AA6F7,
                                    0x9298F5, 0xA88BEB, 0xDD81C5, 0xF8848A, 0xF59A4C]

    static func rgb(_ h: UInt32) -> (Double, Double, Double) {
        (Double(h >> 16 & 0xFF) / 255, Double(h >> 8 & 0xFF) / 255, Double(h & 0xFF) / 255)
    }

    static let ramp: [Color] = rampHex.map { let c = rgb($0); return Color(red: c.0, green: c.1, blue: c.2) }

    /// Colour on the scale at 0…1. A straight blend between ramp samples,
    /// which are close enough together to stay on the OKLCH path.
    static func color(at t: Double) -> Color {
        let x = min(1, max(0, t)) * Double(rampHex.count - 1)
        let i = min(rampHex.count - 2, Int(x)), f = x - Double(i)
        let a = rgb(rampHex[i]), b = rgb(rampHex[i + 1])
        return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
    }

    /// The ramp laid along a circle that's been rotated to the scale's
    /// start: 0…`span` is the scale, and the gap is split between the two
    /// end colours so the round start cap stays green.
    static func ringGradient(span: Double) -> Gradient {
        var stops = ramp.enumerated().map { i, c in
            Gradient.Stop(color: c, location: span * Double(i) / Double(ramp.count - 1))
        }
        stops.append(.init(color: ramp.last!, location: span + (1 - span) / 2))
        stops.append(.init(color: ramp.first!, location: span + (1 - span) / 2 + 0.0001))
        stops.append(.init(color: ramp.first!, location: 1))
        return Gradient(stops: stops)
    }
}

/// Today's "how dialed in am I" score, 0…100, from the three things you
/// log every day. Shared so Home and the widget always agree.
enum DialedScore {
    static func compute(waterOz: Double, waterTargetOz: Double,
                        protein: Double, proteinTarget: Double,
                        calories: Double, calorieTarget: Double) -> Int {
        let water = waterTargetOz > 0 ? min(1, waterOz / waterTargetOz) : 0
        let prot = proteinTarget > 0 ? min(1, protein / proteinTarget) : 0
        // Calories: full marks for logging and staying at or under target,
        // fading to nothing by 25% over.
        let cal: Double
        if calories <= 0 || calorieTarget <= 0 {
            cal = 0
        } else if calories <= calorieTarget {
            cal = 1
        } else {
            cal = max(0, 1 - (calories - calorieTarget) / (calorieTarget * 0.25))
        }
        return Int((100 * (0.35 * water + 0.40 * prot + 0.25 * cal)).rounded())
    }
}

/// Ring + graduated scale + knob, turned to `value` (0…1). The knob face
/// shows `label` (e.g. the score); the pointer becomes a dot on its rim.
struct DialGauge: View {
    var value: Double
    var label: String? = nil
    var caption: String? = nil
    var dark: Bool = false

    private static let start = 135.0, sweep = 270.0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let k = side / 724            // icon units (ring outer edge 362)
            let v = min(1, max(0, value))
            let angle = Self.start + Self.sweep * v
            let ink = dark ? Color.white : Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x19 / 255)

            ZStack {
                // Track, then the lit part of the ring.
                Circle()
                    .trim(from: 0, to: Self.sweep / 360)
                    .stroke(ink.opacity(dark ? 0.14 : 0.08), style: StrokeStyle(lineWidth: 92 * k, lineCap: .round))
                    .rotationEffect(.degrees(Self.start))
                    .frame(width: 632 * k, height: 632 * k)
                Circle()
                    .trim(from: 0, to: max(0.001, Self.sweep / 360 * v))
                    .stroke(AngularGradient(gradient: DialPalette.ringGradient(span: Self.sweep / 360),
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 92 * k, lineCap: .round))
                    .rotationEffect(.degrees(Self.start))
                    .frame(width: 632 * k, height: 632 * k)

                // Scale between ring and knob, lit up to the value.
                ForEach(0...27, id: \.self) { i in
                    let f = Double(i) / 27
                    let major = i % 3 == 0
                    Capsule()
                        .fill(f <= v + 1e-6 ? DialPalette.color(at: f) : ink.opacity(dark ? 0.22 : 0.16))
                        .frame(width: (major ? 30 : 21) * k, height: (major ? 11 : 7) * k)
                        .offset(x: (major ? 235 : 239.5) * k)
                        .rotationEffect(.degrees(Self.start + Self.sweep * f))
                }

                // Knob.
                Circle()
                    .fill(LinearGradient(colors: dark ? [Color(white: 0.30), Color(white: 0.16)] : [.white, Color(white: 0.93)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(dark ? 0.35 : 1), .black.opacity(0.08)],
                                                            startPoint: .top, endPoint: .bottom), lineWidth: 6 * k))
                    .frame(width: 400 * k, height: 400 * k)
                    .shadow(color: .black.opacity(dark ? 0.5 : 0.16), radius: 18 * k, y: 14 * k)
                Circle()
                    .fill(ink)
                    .frame(width: 34 * k, height: 34 * k)
                    .offset(x: 160 * k)
                    .rotationEffect(.degrees(angle))

                if let label {
                    VStack(spacing: 0) {
                        Text(label)
                            .font(.system(size: 120 * k, weight: .bold, design: .rounded))
                            .foregroundColor(ink)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if let caption {
                            Text(caption)
                                .font(.system(size: 46 * k, weight: .semibold))
                                .foregroundColor(ink.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 280 * k)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
