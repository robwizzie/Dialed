//
//  HomeCharts.swift
//  Dialed
//
//  Tiny, dependency-free chart marks for the Home tiles: a smooth
//  sparkline, a bar strip, a half-ring gauge and the water bottle.
//  Deliberately not Swift Charts — these are decorative glyphs that need
//  to render instantly in a 170pt tile, with no axes.
//

import SwiftUI

// MARK: - Sparkline

/// Smooth line through `values`, scaled to fill the frame.
struct NekaSparkline: View {
    let values: [Double]
    var color: Color = Neka.ink
    var lineWidth: CGFloat = 1.6
    var fill: Bool = false
    var showsEndDot: Bool = true

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size)
            ZStack {
                if fill, points.count > 1 {
                    Self.smoothPath(points)
                        .appending(closingTo: geo.size)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        ))
                }
                Self.smoothPath(points)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if showsEndDot, let last = points.last {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Neka.surface, lineWidth: 1.5))
                        .position(last)
                }
            }
        }
    }

    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else {
            if values.count == 1 { return [CGPoint(x: size.width, y: size.height / 2)] }
            return []
        }
        let range = max(hi - lo, 0.0001)
        let inset: CGFloat = 4
        return values.enumerated().map { i, v in
            let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
            let y = inset + (1 - CGFloat((v - lo) / range)) * (size.height - inset * 2)
            return CGPoint(x: x, y: y)
        }
    }

    /// Quadratic curves through segment midpoints — a cheap, pleasant smooth.
    static func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(
                x: (points[i].x + points[i + 1].x) / 2,
                y: (points[i].y + points[i + 1].y) / 2
            )
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

private extension Path {
    /// Close an open line down to the bottom edge for an area fill.
    func appending(closingTo size: CGSize) -> Path {
        var p = self
        guard let current = p.currentPoint else { return p }
        p.addLine(to: CGPoint(x: current.x, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Bars

/// Vertical bar strip. The last bar is drawn in the accent color.
struct NekaBars: View {
    let values: [Double]
    var color: Color = Neka.ink
    var muted: Color = Neka.muted
    var spacing: CGFloat = 4
    var minFraction: CGFloat = 0.12

    var body: some View {
        GeometryReader { geo in
            let hi = max(values.max() ?? 1, 0.0001)
            let count = max(values.count, 1)
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    let fraction = max(minFraction, CGFloat(v / hi))
                    Capsule()
                        .fill(i == values.count - 1 ? color : muted)
                        .frame(width: barWidth, height: geo.size.height * fraction)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }
}

// MARK: - Gauge

/// Upper half-ring with a marker at `progress` (0…1).
struct NekaHalfGauge: View {
    let progress: Double
    var colors: [Color] = [Neka.green, Neka.amber, Neka.rose]
    var lineWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width / 2, geo.size.height) - lineWidth
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height - lineWidth / 2)
            let clamped = max(0, min(1, progress))
            let angle = Angle.degrees(180 + 180 * clamped)
            let marker = CGPoint(
                x: center.x + radius * cos(CGFloat(angle.radians)),
                y: center.y + radius * sin(CGFloat(angle.radians))
            )
            ZStack {
                Path { p in
                    p.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                }
                .stroke(
                    LinearGradient(colors: colors.map { $0.opacity(0.35) }, startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                // Fine tick ring inside, like the reference.
                Path { p in
                    p.addArc(center: center, radius: radius - lineWidth - 4, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                }
                .stroke(Neka.hairline, style: StrokeStyle(lineWidth: 1, dash: [1, 4]))

                Circle()
                    .fill(Neka.blue)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Neka.surface, lineWidth: 2))
                    .shadow(color: Neka.blue.opacity(0.4), radius: 4)
                    .position(marker)
            }
        }
    }
}

// MARK: - Water bottle

/// A smart-bottle glyph that fills to `progress`.
struct NekaBottle: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let neckH = h * 0.14
            let bodyH = h - neckH
            ZStack(alignment: .bottom) {
                // Fill
                RoundedRectangle(cornerRadius: w * 0.28, style: .continuous)
                    .fill(Neka.surface.opacity(0.7))
                    .frame(width: w, height: bodyH)
                RoundedRectangle(cornerRadius: w * 0.28, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Neka.sky.opacity(0.55), Neka.sky],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: w, height: bodyH * max(0.04, min(1, progress)))
                    .animation(.spring(response: 0.8, dampingFraction: 0.8), value: progress)
                RoundedRectangle(cornerRadius: w * 0.28, style: .continuous)
                    .stroke(Neka.sky.opacity(0.45), lineWidth: 1.2)
                    .frame(width: w, height: bodyH)
            }
            .clipShape(RoundedRectangle(cornerRadius: w * 0.28, style: .continuous))
            .frame(width: w, height: h, alignment: .bottom)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Neka.sky.opacity(0.55))
                    .frame(width: w * 0.5, height: neckH * 0.8)
            }
        }
    }
}

// MARK: - Mini ring

/// Small progress ring used in the Body State strip.
struct NekaMiniRing: View {
    let progress: Double
    let colors: [Color]
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Neka.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: colors + [colors.first ?? .clear], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.9, dampingFraction: 0.85), value: progress)
        }
    }
}
