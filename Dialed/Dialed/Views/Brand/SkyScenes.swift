//
//  SkyScenes.swift
//  Dialed
//
//  Living skies drawn in SwiftUI, no image assets. MorningSky reacts to
//  last night's score: a radiant sunrise with turning rays (85+), a mellow
//  dawn (70–84), a hazy morning behind cloud (50–69), or a grey drizzle.
//  NightSky is tonight: a crescent moon and twinkling stars, warmer and
//  moodier the more sleep you owe. Clouds drift and stars twinkle unless
//  Reduce Motion is on.
//

import SwiftUI

// MARK: - Morning

struct MorningSky: View {
    let tier: SleepVisuals.MorningTier

    init(score: Int?) {
        tier = SleepVisuals.MorningTier(score: score ?? 72)
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(colors: Self.skyColors(tier, dark: scheme == .dark),
                                   startPoint: .top, endPoint: .bottom)
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
            let size = h * 0.42
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
            .position(x: w * 0.78, y: h * 0.42)
        case .mellow:
            let size = h * 0.36
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
            .position(x: w * 0.76, y: h * 0.62)
        case .hazy:
            Circle()
                .fill(Color(hex: "FFF1D6").opacity(0.55))
                .frame(width: h * 0.32, height: h * 0.32)
                .blur(radius: 6)
                .position(x: w * 0.74, y: h * 0.4)
        case .drizzly:
            EmptyView()
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
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(colors: Self.colors(SleepVisuals.DebtTier(debtHours: debtHours)),
                                   startPoint: .top, endPoint: .bottom)
                    Canvas { ctx, size in
                        for i in 0..<46 {
                            let seed = Double(i) * 57.31
                            let x = (seed * 9.7).truncatingRemainder(dividingBy: Double(size.width))
                            let y = (seed * 3.3).truncatingRemainder(dividingBy: Double(size.height) * 0.75)
                            let twinkle = 0.45 + 0.55 * abs(sin(t * (0.6 + Double(i % 5) * 0.25) + seed))
                            let r = 0.8 + Double(i % 3) * 0.55
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                     with: .color(.white.opacity(twinkle * 0.85)))
                        }
                    }
                    // Crescent moon with a soft glow.
                    ZStack {
                        Circle().fill(Color(hex: "FFF4D2").opacity(0.18))
                            .frame(width: h * 0.62, height: h * 0.62)
                            .blur(radius: 14)
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: "FFF6DC"), Color(hex: "F5DFA8")], startPoint: .top, endPoint: .bottom))
                            .frame(width: h * 0.3, height: h * 0.3)
                            .mask(
                                ZStack {
                                    Rectangle()
                                    Circle()
                                        .frame(width: h * 0.3, height: h * 0.3)
                                        .offset(x: h * 0.09, y: -h * 0.05)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                            )
                            .rotationEffect(.degrees(-18 + 2 * sin(t * 0.3)))
                    }
                    .position(x: w * 0.84, y: h * 0.26)
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

/// The night's arc: wind-down, bedtime and wake along a horizon, with a
/// glowing dot for now.
struct NightArc: View {
    let tonight: SleepVisuals.Tonight
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let start = min(now, tonight.windDown)
            let point = { (date: Date) -> CGPoint in
                let f = SleepVisuals.fraction(date, from: start, to: tonight.wake)
                let angle = Double.pi * (1 - f)
                return CGPoint(x: w / 2 + CGFloat(cos(angle)) * (w / 2 - 14),
                               y: h - CGFloat(sin(angle)) * (h - 14))
            }
            ZStack {
                Path { p in
                    p.addArc(center: CGPoint(x: w / 2, y: h), radius: w / 2 - 14,
                             startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                }
                .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))
                // Asleep stretch, bedtime → wake.
                Path { p in
                    let a = 180 * (1 - SleepVisuals.fraction(tonight.bedtime, from: start, to: tonight.wake))
                    p.addArc(center: CGPoint(x: w / 2, y: h), radius: w / 2 - 14,
                             startAngle: .degrees(180 + (180 - a)), endAngle: .degrees(0), clockwise: false)
                }
                .stroke(LinearGradient(colors: [Color(hex: "B49CFF"), Color(hex: "FFD38A")], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                marker(point(tonight.windDown), "sparkles")
                marker(point(tonight.bedtime), "moon.fill")
                marker(point(tonight.wake), "sun.max.fill")
                Circle().fill(.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .white.opacity(0.8), radius: 6)
                    .position(point(now))
            }
        }
    }

    private func marker(_ p: CGPoint, _ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(.white.opacity(0.18)))
            .position(p)
    }
}
