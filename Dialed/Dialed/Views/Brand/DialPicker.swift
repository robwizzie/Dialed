//
//  DialPicker.swift
//  Dialed
//
//  A knob you twist to pick a number: the Dialed dial as an input. Drag
//  round the knob (anywhere on it) and it turns, the ring fills and the
//  scale lights up, with a selection click for every step — like a real
//  detented knob. VoiceOver can swipe up/down to adjust.
//
//  Used for water amounts and fine-tuning a weigh-in.
//

import SwiftUI

struct DialPicker: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var unit: String
    var format: String = "%.0f"

    @Environment(\.colorScheme) private var scheme
    @State private var lastAngle: Double?
    /// Unsnapped value while dragging, so slow turns still add up.
    @State private var raw: Double?
    @State private var hitEnd = false

    private static let sweep = 270.0

    private var fraction: Double {
        (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            DialGauge(value: fraction, label: String(format: format, value), caption: unit, dark: scheme == .dark)
                .frame(width: size, height: size)
                .position(center)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in turn(to: g.location, around: center, size: size) }
                        .onEnded { _ in lastAngle = nil; raw = nil }
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: value)
        .sensoryFeedback(.impact(weight: .medium), trigger: hitEnd) { _, new in new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit)
        .accessibilityValue("\(String(format: format, value)) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            @unknown default: break
            }
        }
    }

    private func turn(to p: CGPoint, around c: CGPoint, size: CGFloat) {
        let dx = p.x - c.x, dy = p.y - c.y
        // Ignore the dead centre, where the angle jumps about.
        guard dx * dx + dy * dy > Double(size * size) * 0.004 else { return }
        let angle = atan2(dy, dx) * 180 / .pi
        defer { lastAngle = angle }
        guard let last = lastAngle else { return }
        var delta = angle - last
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let span = range.upperBound - range.lowerBound
        let next = (raw ?? value) + delta / Self.sweep * span
        raw = min(range.upperBound, max(range.lowerBound, next))
        set(next)
    }

    private func set(_ v: Double) {
        let snapped = ((v / step).rounded() * step)
        let clamped = min(range.upperBound, max(range.lowerBound, snapped))
        let atEnd = clamped == range.lowerBound || clamped == range.upperBound
        if atEnd != hitEnd { hitEnd = atEnd }
        if clamped != value { value = clamped }
    }
}

#Preview {
    struct Demo: View {
        @State var oz = 16.0
        var body: some View {
            DialPicker(value: $oz, range: 0...64, step: 2, unit: "oz")
                .frame(width: 220)
                .padding()
                .background(Neka.paper)
        }
    }
    return Demo()
}
