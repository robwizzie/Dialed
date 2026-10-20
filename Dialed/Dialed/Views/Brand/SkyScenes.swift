//
//  SkyScenes.swift
//  Dialed
//
//  Living skies drawn in SwiftUI, no image assets. MorningSky reacts to
//  last night's score: a radiant sunrise with turning rays (85+), a mellow
//  dawn (70–84), a hazy morning behind cloud (50–69), or a grey drizzle.
//  NightSky is tonight: a quiet gradient, a few faint stars and a small
//  crescent, warmer and moodier the more sleep you owe. Clouds drift and stars twinkle unless
//  Reduce Motion is on.
//

import SwiftUI

// MARK: - Morning

struct MorningSky: View {
    let tier: SleepVisuals.MorningTier
    /// When set, the sun climbs an arc from the horizon and sits as high as
    /// the score (0…1, 1 = the top), with the day's path drawn faintly.
    let sunProgress: Double?

    init(score: Int?, sunOnArc: Bool = false) {
        tier = SleepVisuals.MorningTier(score: score ?? 72)
        sunProgress = sunOnArc ? score.map { SleepVisuals.arcProgress(score: $0) } : nil
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(colors: Self.skyColors(tier, dark: scheme == .dark),
                                   startPoint: .top, endPoint: .bottom)
                    if let p = sunProgress { arcTrack(progress: p, w: w, h: h) }
                    sun(t: t, w: w, h: h)
                    clouds(t: t, w: w, h: h)
                    if tier == .drizzly { rain(t: t, w: w, h: h) }
                    hills(w: w, h: h)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Palette

    static func skyColors(_ tier: SleepVisuals.MorningTier, dark: Bool) -> [Color] {
        switch (tier, dark) {
        case (.radiant, false): return [Color(hex: "7EC8FF"), Color(hex: "FFD7A0"), Color(hex: "FFB38A")]
        case (.radiant, true):  return [Color(hex: "1E3A6E"), Color(hex: "C2664A"), Color(hex: "F2A35E")]
        case (.mellow, false):  return [Color(hex: "A9CFF5"), Color(hex: "F6E2C8"), Color(hex: "F3CDB8")]
        case (.mellow, true):   return [Color(hex: "23365C"), Color(hex: "7D5A6E"), Color(hex: "C08463")]
        case (.hazy, false):    return [Color(hex: "C6D3E2"), Color(hex: "E7E4E0"), Color(hex: "E3D9CF")]
        case (.hazy, true):     return [Color(hex: "2B3442"), Color(hex: "4E5563"), Color(hex: "6B6670")]
        case (.drizzly, false): return [Color(hex: "9AA6B6"), Color(hex: "BCC4CF"), Color(hex: "CDD2D9")]
        case (.drizzly, true):  return [Color(hex: "1C222B"), Color(hex: "2F3742"), Color(hex: "3D4550")]
        }
    }

    /// The score ring's colors match the sky.
    static func ringColors(_ tier: SleepVisuals.MorningTier) -> [Color] {
        switch tier {
        case .radiant: return [Color(hex: "FFC94D"), Color(hex: "FF8A4C"), Color(hex: "FF6F91"), Color(hex: "FFC94D")]
        case .mellow:  return [Color(hex: "FFD38A"), Color(hex: "7EC8FF"), Color(hex: "B49CFF"), Color(hex: "FFD38A")]
        case .hazy:    return [Color(hex: "9FB4CC"), Color(hex: "B49CFF"), Color(hex: "9FB4CC")]
        case .drizzly: return [Color(hex: "7D8897"), Color(hex: "9FB4CC"), Color(hex: "7D8897")]
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func sun(t: Double, w: CGFloat, h: CGFloat) -> some View {
        switch tier {
        case .radiant:
            let size = h * (sunProgress == nil ? 0.42 : 0.2)
            ZStack {
                // Turning rays.
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(Color(hex: "FFE6A6").opacity(0.55))
                        .frame(width: size * 0.07, height: size * 0.34)
                        .offset(y: -size * 0.78)
                        .rotationEffect(.degrees(Double(i) * 30 + t * 6))
                }
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "FFF3C4").opacity(0.9), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 1.3))
                    .frame(width: size * 2.6, height: size * 2.6)
                    .scaleEffect(1 + 0.04 * sin(t * 1.4))
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "FFE58A"), Color(hex: "FFB347")], startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
                    .shadow(color: Color(hex: "FFB347").opacity(0.6), radius: 18)
            }
            .position(sunPosition(w: w, h: h, fallback: CGPoint(x: w * 0.78, y: h * 0.42)))
        case .mellow:
            let size = h * (sunProgress == nil ? 0.36 : 0.18)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "FFE7B0").opacity(0.75), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 1.1))
                    .frame(width: size * 2.2, height: size * 2.2)
                    .scaleEffect(1 + 0.03 * sin(t * 1.1))
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "FFE3A0"), Color(hex: "FFC27A")], startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
            }
            .position(sunPosition(w: w, h: h, fallback: CGPoint(x: w * 0.76, y: h * 0.62)))
        case .hazy:
            Circle()
                .fill(Color(hex: "FFF1D6").opacity(0.55))
                .frame(width: h * (sunProgress == nil ? 0.32 : 0.18), height: h * (sunProgress == nil ? 0.32 : 0.18))
                .blur(radius: 6)
                .position(sunPosition(w: w, h: h, fallback: CGPoint(x: w * 0.74, y: h * 0.4)))
        case .drizzly:
            EmptyView()
        }
    }

    // MARK: Score arc

    /// A point on the sun's half-circle path, `t` 0 (left horizon) → 1
    /// (right horizon). Kept to the right side, clear of the greeting.
    private func pathPoint(_ t: Double, w: CGFloat, h: CGFloat) -> CGPoint {
        let angle = Double.pi * (1 - t)
        let center = CGPoint(x: w * 0.72, y: h * 0.46)
        let rx = w * 0.22, ry = h * 0.34
        return CGPoint(x: center.x + CGFloat(cos(angle)) * rx, y: center.y - CGFloat(sin(angle)) * ry)
    }

    /// The score climbs the left half: 0 on the horizon, 100 at the top.
    private func arcPoint(_ p: Double, w: CGFloat, h: CGFloat) -> CGPoint {
        pathPoint(p / 2, w: w, h: h)
    }

    private func sunPosition(w: CGFloat, h: CGFloat, fallback: CGPoint) -> CGPoint {
        sunProgress.map { arcPoint($0, w: w, h: h) } ?? fallback
    }

    private func arcPath(to t: Double, w: CGFloat, h: CGFloat) -> Path {
        Path { path in
            let steps = 40
            for i in 0...steps {
                let pt = pathPoint(t * Double(i) / Double(steps), w: w, h: h)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
        }
    }

    private func arcTrack(progress: Double, w: CGFloat, h: CGFloat) -> some View {
        let lit: Color = tier == .drizzly || tier == .hazy ? .white.opacity(0.75) : Color(hex: "FFF3C4")
        return ZStack {
            arcPath(to: 1, w: w, h: h)
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
            arcPath(to: progress / 2, w: w, h: h)
                .stroke(lit, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            if tier == .drizzly {
                // No sun on a grey morning; a small marker still shows the score.
                Circle().fill(.white.opacity(0.85))
                    .frame(width: 9, height: 9)
                    .position(arcPoint(progress, w: w, h: h))
            }
        }
    }

    private func clouds(t: Double, w: CGFloat, h: CGFloat) -> some View {
        let style: (count: Int, opacity: Double, tint: Color) = {
            switch tier {
            case .radiant: return (2, 0.85, .white)
            case .mellow:  return (3, 0.8, .white)
            case .hazy:    return (5, 0.75, Color(hex: "F2F2F4"))
            case .drizzly: return (6, 0.9, Color(hex: "8E98A6"))
            }
        }()
        let count = style.count, opacity = style.opacity, tint = style.tint
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let speed = 6 + Double(i % 3) * 3
                let base = Double(i) / Double(count)
                let x = (base * Double(w + 160) + t * speed).truncatingRemainder(dividingBy: Double(w + 160)) - 80
                CloudShape()
                    .fill(tint.opacity(opacity - Double(i % 2) * 0.15))
                    .frame(width: 90 + CGFloat(i % 3) * 26, height: 34 + CGFloat(i % 2) * 10)
                    .position(x: CGFloat(x), y: h * (0.18 + 0.12 * CGFloat(i % 3)))
                    .blur(radius: tier == .hazy ? 2 : 0)
            }
        }
    }

    private func rain(t: Double, w: CGFloat, h: CGFloat) -> some View {
        Canvas { ctx, size in
            for i in 0..<28 {
                let seed = Double(i) * 37.13
                let x = (seed * 13).truncatingRemainder(dividingBy: Double(size.width))
                let fall = (t * 120 + seed * 7).truncatingRemainder(dividingBy: Double(size.height))
                var p = Path()
                p.move(to: CGPoint(x: x, y: fall))
                p.addLine(to: CGPoint(x: x - 3, y: fall + 10))
                ctx.stroke(p, with: .color(Color(hex: "C9D6E6").opacity(0.7)), lineWidth: 1.2)
            }
        }
    }

    private func hills(w: CGFloat, h: CGFloat) -> some View {
        let bright = tier == .radiant || tier == .mellow
        let colors: (back: Color, front: Color) = {
            switch (bright, scheme == .dark) {
            case (true, false):  return (Color(hex: "A8D8B0"), Color(hex: "7CC28E"))
            case (true, true):   return (Color(hex: "2F4A3E"), Color(hex: "23392F"))
            case (false, false): return (Color(hex: "AEB9B2"), Color(hex: "93A098"))
            case (false, true):  return (Color(hex: "262E2C"), Color(hex: "1C2321"))
            }
        }()
        let back = colors.back, front = colors.front
        return ZStack {
            HillShape(peak: 0.3, height: 0.26).fill(back)
            HillShape(peak: 0.72, height: 0.18).fill(front)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Night

struct NightSky: View {
    /// Sleep owed this week; more debt → warmer, moodier sky.
    let debtHours: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func colors(_ tier: SleepVisuals.DebtTier) -> [Color] {
        switch tier {
        case .rested: return [Color(hex: "0B1433"), Color(hex: "1C2A63"), Color(hex: "36478F")]
        case .owed:   return [Color(hex: "120F33"), Color(hex: "2B1E62"), Color(hex: "51408F")]
        case .heavy:  return [Color(hex: "1A0D2E"), Color(hex: "3D1A55"), Color(hex: "7A3D72")]
        }
    }

    var body: some View {
        // A slow twinkle is enough; the card isn't the show.
        SwiftUI.TimelineView(.animation(minimumInterval: 1 / 8, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(colors: Self.colors(SleepVisuals.DebtTier(debtHours: debtHours)),
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    // A few faint stars, mostly up and to the right, away from the text.
                    Canvas { ctx, size in
                        for i in 0..<18 {
                            let seed = Double(i) * 57.31
                            let x = size.width * (0.35 + 0.65 * (seed * 0.137).truncatingRemainder(dividingBy: 1))
                            let y = size.height * 0.7 * (seed * 0.071).truncatingRemainder(dividingBy: 1)
                            let twinkle = 0.35 + 0.35 * abs(sin(t * (0.4 + Double(i % 4) * 0.15) + seed))
                            let r = 0.6 + Double(i % 3) * 0.4
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                     with: .color(.white.opacity(twinkle * 0.6)))
                        }
                    }
                    // A small crescent tucked in the top corner.
                    let d = min(34, h * 0.2)
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "FFF6DC"), Color(hex: "F5DFA8")], startPoint: .top, endPoint: .bottom))
                        .frame(width: d, height: d)
                        .mask(
                            ZStack {
                                Rectangle()
                                Circle()
                                    .frame(width: d, height: d)
                                    .offset(x: d * 0.32, y: -d * 0.18)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        )
                        .shadow(color: Color(hex: "FFF4D2").opacity(0.35), radius: 8)
                        .rotationEffect(.degrees(-18))
                        .position(x: w - 30, y: 30)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes

struct CloudShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.minX, y: r.minY + r.height * 0.35, width: r.width * 0.5, height: r.height * 0.65))
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.22, y: r.minY, width: r.width * 0.5, height: r.height * 0.9))
        p.addEllipse(in: CGRect(x: r.minX + r.width * 0.48, y: r.minY + r.height * 0.25, width: r.width * 0.52, height: r.height * 0.75))
        return p
    }
}

/// A soft hill along the bottom; `peak` is where it crests (0…1 across),
/// `height` how tall it is as a share of the frame.
struct HillShape: Shape {
    var peak: CGFloat
    var height: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.maxY - r.height * height
        p.move(to: CGPoint(x: r.minX, y: r.maxY - r.height * height * 0.45))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * peak, y: top),
                       control: CGPoint(x: r.minX + r.width * peak * 0.5, y: top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - r.height * height * 0.55),
                       control: CGPoint(x: r.minX + r.width * (peak + (1 - peak) * 0.5), y: top))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
