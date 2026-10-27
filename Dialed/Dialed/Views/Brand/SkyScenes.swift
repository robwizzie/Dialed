//
//  SkyScenes.swift
//  Dialed
//
//  Living skies drawn in SwiftUI, no image assets. DaySky reacts to a
//  score — a radiant sky with turning rays (85+), a mellow one (70–84), a
//  hazy one behind cloud (50–69), or a grey drizzle — in the light of the
//  time of day: sunrise, midday, golden hour or night.
//  NightSky is tonight: a quiet gradient, a few faint stars and a small
//  crescent, warmer and moodier the more sleep you owe. Clouds drift and stars twinkle unless
//  Reduce Motion is on.
//

import SwiftUI

// MARK: - Day

/// Set by a scrolling page so animated skies hold still mid-scroll (one
/// less layer redrawing every frame while you fling). Only the skies read
/// it, so flipping it doesn't rebuild the page.
@Observable
final class SkyMotion {
    var isScrolling = false
}

extension View {
    /// Tells skies below when this scroll view is moving (iOS 18+).
    func tracksSkyMotion(_ motion: SkyMotion) -> some View {
        Group {
            if #available(iOS 18.0, *) {
                onScrollPhaseChange { _, phase in motion.isScrolling = phase.isScrolling }
            } else {
                self
            }
        }
        .environment(motion)
    }
}

/// The sky behind the day banner, drawn in one Canvas pass. `tier` is the
/// weather the score earned (radiant → drizzle); `time` sets the light
/// (sunrise, midday blue, golden hour, night). Up top on the right, the
/// score is a dial: a track with ticks, filled to `score` (0…1), with the
/// sun (or tonight's moon) as the knob. Clouds drift behind it (and rain
/// falls) at a modest frame rate, pausing while the page scrolls, while
/// the sky is off screen, and with Reduce Motion.
struct DaySky: View {
    enum Time: Equatable { case morning, midday, evening, night }

    let tier: SleepVisuals.MorningTier
    let time: Time
    /// The banner's score as 0…1; nil hides the dial.
    let score: Double?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SkyMotion.self) private var motion: SkyMotion?
    @State private var onScreen = true

    var body: some View {
        let paused = reduceMotion || !onScreen || (motion?.isScrolling ?? false)
        SwiftUI.TimelineView(.animation(minimumInterval: 1 / 20, paused: paused)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in draw(in: &ctx, size: size, t: t) }
        }
        .modifier(OnScreenTracker(onScreen: $onScreen))
        .accessibilityHidden(true)
    }

    /// Pauses the sky once it scrolls out of view (iOS 18+), or at least
    /// when its screen goes away (iOS 17, where it otherwise never paused).
    private struct OnScreenTracker: ViewModifier {
        @Binding var onScreen: Bool

        func body(content: Content) -> some View {
            if #available(iOS 18.0, *) {
                content.onScrollVisibilityChange(threshold: 0.05) { onScreen = $0 }
            } else {
                content
                    .onAppear { onScreen = true }
                    .onDisappear { onScreen = false }
            }
        }
    }

    // MARK: Drawing

    private var dark: Bool { scheme == .dark }
    private var night: Bool { time == .night }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: Self.skyColors(tier, time: time, dark: dark)),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        if night { stars(&ctx, w: w, h: h, t: t) }
        clouds(&ctx, w: w, t: t)
        if tier == .drizzly && !night { rain(&ctx, w: w, h: h, t: t) }
        if let score { dial(&ctx, score: min(1, max(0, score)), w: w, t: t) }
        hills(&ctx, w: w, h: h)
    }

    // MARK: Score dial

    /// The dial sits top right, clear of the score and text on the left.
    private func dialCenter(_ w: CGFloat) -> CGPoint { CGPoint(x: w - 86, y: 94) }
    private let radius: CGFloat = 58

    /// A point on the dial, 0 on the left end → 1 on the right.
    private func point(_ p: Double, _ w: CGFloat, inset: CGFloat = 0) -> CGPoint {
        let c = dialCenter(w), r = radius - inset
        let angle = Double.pi * (1 - p)
        return CGPoint(x: c.x + CGFloat(cos(angle)) * r, y: c.y - CGFloat(sin(angle)) * r)
    }

    private func arc(to p: Double, _ w: CGFloat) -> Path {
        Path { path in
            let steps = max(2, Int(48 * p))
            for i in 0...steps {
                let pt = point(p * Double(i) / Double(steps), w)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
        }
    }

    private var fillColors: [Color] {
        if night { return [Color(hex: "B9A8FF"), Color(hex: "F5DFA8")] }
        switch tier {
        case .radiant: return [Color(hex: "FFE9A8"), Color(hex: "FFB347")]
        case .mellow:  return [Color(hex: "FFF1CC"), Color(hex: "FFC27A")]
        case .hazy:    return [.white.opacity(0.7), Color(hex: "FFF1D6")]
        case .drizzly: return [.white.opacity(0.6), .white.opacity(0.95)]
        }
    }

    private func dial(_ ctx: inout GraphicsContext, score p: Double, w: CGFloat, t: Double) {
        // Track.
        ctx.stroke(arc(to: 1, w), with: .color(.white.opacity(night ? 0.16 : 0.32)),
                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
        // Ticks every 10 points, inside the track; 0, 50 and 100 longer.
        var ticks = Path()
        for k in 0...10 {
            let major = k % 5 == 0
            ticks.move(to: point(Double(k) / 10, w, inset: 8))
            ticks.addLine(to: point(Double(k) / 10, w, inset: major ? 15 : 12))
        }
        ctx.stroke(ticks, with: .color(.white.opacity(night ? 0.35 : 0.6)),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        // Fill up to the score.
        let left = point(0, w), right = point(1, w)
        ctx.stroke(arc(to: p, w), with: .linearGradient(Gradient(colors: fillColors), startPoint: left, endPoint: right),
                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
        knob(&ctx, at: point(p, w), t: t)
    }

    private func knob(_ ctx: inout GraphicsContext, at p: CGPoint, t: Double) {
        if night {
            moon(&ctx, at: p, d: 27)
            return
        }
        switch tier {
        case .radiant, .mellow:
            let radiant = tier == .radiant
            let size: CGFloat = radiant ? 34 : 31
            let glow = size * 1.15 * (1 + 0.04 * sin(t * 1.3))
            let evening = time == .evening
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: evening ? "FFD6A0" : "FFF3C4").opacity(radiant ? 0.85 : 0.65), .clear]),
                                           center: p, startRadius: size * 0.3, endRadius: glow))
            if radiant {
                // Short turning rays.
                let rw: CGFloat = 2.4, rh: CGFloat = 6
                for i in 0..<12 {
                    var r = ctx
                    r.translateBy(x: p.x, y: p.y)
                    r.rotate(by: .degrees(Double(i) * 30 + t * 6))
                    r.fill(Path(roundedRect: CGRect(x: -rw / 2, y: -size * 0.5 - 4 - rh, width: rw, height: rh), cornerRadius: rw / 2),
                           with: .color(Color(hex: "FFE6A6").opacity(0.7)))
                }
            }
            let disc = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            let fill = evening ? ["FFD27A", "FF8F52"] : radiant ? ["FFE58A", "FFB347"] : ["FFE3A0", "FFC27A"]
            ctx.fill(Path(ellipseIn: disc),
                     with: .linearGradient(Gradient(colors: fill.map { Color(hex: $0) }),
                                           startPoint: CGPoint(x: p.x, y: disc.minY), endPoint: CGPoint(x: p.x, y: disc.maxY)))
            ctx.stroke(Path(ellipseIn: disc.insetBy(dx: 0.75, dy: 0.75)), with: .color(.white.opacity(0.55)), lineWidth: 1.5)
        case .hazy:
            let size: CGFloat = 28
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - size, y: p.y - size, width: size * 2, height: size * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: "FFF1D6").opacity(0.75), .clear]),
                                           center: p, startRadius: size * 0.35, endRadius: size))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)),
                     with: .color(Color(hex: "FFF4E0").opacity(0.9)))
        case .drizzly:
            let d: CGFloat = 16
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - d / 2 - 3, y: p.y - d / 2 - 3, width: d + 6, height: d + 6)),
                       with: .color(.white.opacity(0.4)), lineWidth: 2)
        }
    }

    // MARK: Weather and land

    private func clouds(_ ctx: inout GraphicsContext, w: CGFloat, t: Double) {
        let style: (count: Int, opacity: Double, tint: Color) = {
            if night { return (2, 0.14, .white) }
            switch tier {
            case .radiant: return (2, 0.9, .white)
            case .mellow:  return (3, 0.85, .white)
            case .hazy:    return (4, 0.8, Color(hex: "F4F4F6"))
            case .drizzly: return (4, 0.95, Color(hex: "939DAB"))
            }
        }()
        // Clouds drift across the right side only, behind the dial, so they
        // never sit on the score.
        let start = Double(w * 0.42), span = Double(w * 0.58 + 120)
        let shape = CloudShape()
        for i in 0..<style.count {
            let speed = 4 + Double(i % 3) * 2.5
            let base = Double(i) / Double(style.count)
            let x = start + (base * span + t * speed).truncatingRemainder(dividingBy: span) - 50
            let cw = 64 + CGFloat(i % 3) * 16, ch = 24 + CGFloat(i % 2) * 7
            let y = 30 + CGFloat(i % 3) * 20
            let rect = CGRect(x: CGFloat(x) - cw / 2, y: y - ch / 2, width: cw, height: ch)
            let o = style.opacity - Double(i % 2) * 0.15
            ctx.fill(shape.path(in: rect),
                     with: .linearGradient(Gradient(colors: [style.tint.opacity(o), style.tint.opacity(o * 0.75)]),
                                           startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }
    }

    private func rain(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, t: Double) {
        var drops = Path()
        let left = Double(w * 0.42), width = Double(w * 0.58)
        for i in 0..<18 {
            let seed = Double(i) * 37.13
            let x = left + (seed * 13).truncatingRemainder(dividingBy: width)
            let fall = 40 + (t * 90 + seed * 7).truncatingRemainder(dividingBy: Double(h * 0.5))
            drops.move(to: CGPoint(x: x, y: fall))
            drops.addLine(to: CGPoint(x: x - 2.5, y: fall + 8))
        }
        ctx.stroke(drops, with: .color(Color(hex: "D3DEEB").opacity(0.75)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    private func stars(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, t: Double) {
        for i in 0..<24 {
            let seed = Double(i) * 57.31
            let x = w * (0.08 + 0.9 * (seed * 0.137).truncatingRemainder(dividingBy: 1))
            let y = h * 0.55 * (seed * 0.071).truncatingRemainder(dividingBy: 1)
            let twinkle = 0.35 + 0.35 * abs(sin(t * (0.4 + Double(i % 4) * 0.15) + seed))
            let r = 0.6 + Double(i % 3) * 0.4
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(twinkle * 0.6)))
        }
    }

    /// A crescent: a full disc with an offset disc cut out of it.
    private func moon(_ ctx: inout GraphicsContext, at c: CGPoint, d: CGFloat) {
        let disc = CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
        ctx.fill(Path(ellipseIn: disc.insetBy(dx: -d * 0.6, dy: -d * 0.6)),
                 with: .radialGradient(Gradient(colors: [Color(hex: "FFF4D2").opacity(0.3), .clear]),
                                       center: c, startRadius: d * 0.3, endRadius: d * 1.1))
        ctx.drawLayer { layer in
            layer.fill(Path(ellipseIn: disc),
                       with: .linearGradient(Gradient(colors: [Color(hex: "FFF6DC"), Color(hex: "F5DFA8")]),
                                             startPoint: CGPoint(x: c.x, y: disc.minY), endPoint: CGPoint(x: c.x, y: disc.maxY)))
            layer.blendMode = .destinationOut
            layer.fill(Path(ellipseIn: disc.offsetBy(dx: d * 0.34, dy: -d * 0.2)), with: .color(.black))
        }
    }

    private func hills(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let bright = tier == .radiant || tier == .mellow
        let colors: (back: String, front: String) = {
            switch (time, bright, dark) {
            case (.night, _, _):          return ("1A2740", "121C30")
            case (.evening, _, false):    return (bright ? "A6CBA6" : "A3ABA6", bright ? "7FB38D" : "88938C")
            case (.evening, _, true):     return ("2A3B36", "1E2B27")
            case (_, true, false):        return ("B2DDB8", "86C796")
            case (_, true, true):         return ("2F4A3E", "23392F")
            case (_, false, false):       return ("B4BEB7", "98A49D")
            case (_, false, true):        return ("262E2C", "1C2321")
            }
        }()
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        func fill(_ shape: HillShape, _ hex: String) {
            let path = shape.path(in: rect)
            let top = path.boundingRect.minY
            ctx.fill(path, with: .linearGradient(Gradient(colors: [Color(hex: hex), Color(hex: hex).opacity(0.85)]),
                                                 startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))
        }
        fill(HillShape(peak: 0.28, height: 0.17), colors.back)
        fill(HillShape(peak: 0.74, height: 0.11), colors.front)
    }

    // MARK: Palette

    static func skyColors(_ tier: SleepVisuals.MorningTier, time: Time, dark: Bool) -> [Color] {
        let hex: [String]
        switch (time, tier, dark) {
        // Sunrise.
        case (.morning, .radiant, false): hex = ["7EC8FF", "FFD7A0", "FFB38A"]
        case (.morning, .radiant, true):  hex = ["1E3A6E", "C2664A", "F2A35E"]
        case (.morning, .mellow, false):  hex = ["A9CFF5", "F6E2C8", "F3CDB8"]
        case (.morning, .mellow, true):   hex = ["23365C", "7D5A6E", "C08463"]
        case (.morning, .hazy, false):    hex = ["C6D3E2", "E7E4E0", "E3D9CF"]
        case (.morning, .hazy, true):     hex = ["2B3442", "4E5563", "6B6670"]
        // Midday blue.
        case (.midday, .radiant, false):  hex = ["4FA8F5", "8FCBFA", "D6ECFB"]
        case (.midday, .radiant, true):   hex = ["123A6B", "1F5A8F", "3A78A8"]
        case (.midday, .mellow, false):   hex = ["7DB7EA", "B4D6F1", "E4EFF6"]
        case (.midday, .mellow, true):    hex = ["1B3557", "2C4D72", "4B6A86"]
        case (.midday, .hazy, false):     hex = ["B3C2D3", "D2DAE2", "E4E6E8"]
        case (.midday, .hazy, true):      hex = ["283240", "3A4452", "4D5562"]
        // Golden hour.
        case (.evening, .radiant, false): hex = ["6A7FD3", "F0A07E", "FFC68C"]
        case (.evening, .radiant, true):  hex = ["1E2558", "8A4A6A", "D9855A"]
        case (.evening, .mellow, false):  hex = ["8390C8", "D9A3A3", "F1C7A4"]
        case (.evening, .mellow, true):   hex = ["252B52", "6B4A68", "A86F5C"]
        case (.evening, .hazy, false):    hex = ["9198AB", "C2B0B2", "DCC9BC"]
        case (.evening, .hazy, true):     hex = ["2A2E3E", "4C4652", "6E5F60"]
        case (.evening, .drizzly, false): hex = ["7D8594", "A0A3AC", "BBB8B8"]
        case (.evening, .drizzly, true):  hex = ["1C2129", "2E3239", "403F44"]
        // Grey all day.
        case (_, .drizzly, false):        hex = ["9AA6B6", "BCC4CF", "CDD2D9"]
        case (_, .drizzly, true):         hex = ["1C222B", "2F3742", "3D4550"]
        // Night: deeper and moodier the rougher the day.
        case (.night, .radiant, _), (.night, .mellow, _): hex = ["0B1433", "1C2A63", "36478F"]
        case (.night, .hazy, _):          hex = ["120F33", "2B1E62", "51408F"]
        }
        return hex.map { Color(hex: $0) }
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

    @State private var onScreen = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: Self.colors(SleepVisuals.DebtTier(debtHours: debtHours)),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Only the stars twinkle, so only they redraw; a slow
                // twinkle is enough, the card isn't the show.
                SwiftUI.TimelineView(.animation(minimumInterval: 1 / 8, paused: reduceMotion || !onScreen)) { context in
                    let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
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
                }
                // A small crescent tucked in the top corner, drawn once.
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
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
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
