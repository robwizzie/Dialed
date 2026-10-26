//
//  NekaScene.swift
//  Dialed
//
//  Full-bleed color moods for screens that lead with one number: a sunlit
//  wash behind the page (citrus Home, lime Body, icy Nutrition, violet
//  Sleep), a big thin headline numeral read straight off it, then an
//  insight pill, a three-up stat row and a frosted capsule CTA. Cards
//  below the hero sit on the wash as usual — it fades into paper.
//

import SwiftUI

extension Neka {

    enum Scene: Equatable {
        case citrus, lime, ice, violet

        /// Top → bottom page wash, ending on paper.
        var stops: [Gradient.Stop] {
            switch self {
            case .citrus:
                return [Self.stop("F2EE5C", "3A3612", 0), Self.stop("F7F4AE", "22210F", 0.38),
                        .init(color: Neka.paper, location: 0.78)]
            case .lime:
                return [Self.stop("CDEE86", "1F3A17", 0), Self.stop("E9F6C8", "172414", 0.4),
                        .init(color: Neka.paper, location: 0.82)]
            case .ice:
                return [Self.stop("B9CCEC", "17283F", 0), Self.stop("DDE7F6", "141C28", 0.45),
                        .init(color: Neka.paper, location: 0.86)]
            case .violet:
                return [Self.stop("6C35E8", "3B1F8A", 0), Self.stop("8F62F0", "281758", 0.45),
                        Self.stop("CDBBF7", "1A1430", 0.75), .init(color: Neka.paper, location: 1)]
            }
        }

        /// The wash's top color — for the status-bar scrim.
        var top: Color { stops[0].color }

        /// Text and icons drawn straight on the wash.
        var ink: Color { self == .violet ? .white : Neka.ink }
        var inkSecondary: Color {
            self == .violet ? Color.white.opacity(0.72) : Neka.inkSecondary
        }
        /// Text on an `ink` fill (selected chips).
        var onInk: Color { self == .violet ? Color(hex: "5B2BD9") : Neka.onInk }

        /// Frosted glass for pills, chips and buttons on the wash.
        var glass: Color {
            Color(light: Color.white.opacity(self == .violet ? 0.16 : 0.5), dark: Color.white.opacity(0.08))
        }
        var glassStroke: Color {
            Color(light: Color.white.opacity(self == .violet ? 0.35 : 0.75), dark: Color.white.opacity(0.12))
        }

        private static func stop(_ light: String, _ dark: String, _ location: CGFloat) -> Gradient.Stop {
            .init(color: Color(light: Color(hex: light), dark: Color(hex: dark)), location: location)
        }
    }

    /// Big, thin numerals for a screen's one headline number.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light)
    }
}

extension View {
    /// The scene's wash, with a soft bloom at the top, behind the whole page.
    func nekaSceneBackground(_ scene: Neka.Scene) -> some View {
        background(
            ZStack {
                Neka.paper
                LinearGradient(stops: scene.stops, startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [Neka.glow.opacity(scene == .violet ? 0.25 : 0.7), Neka.glow.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.14), startRadius: 0, endRadius: 340
                )
            }
            .ignoresSafeArea()
        )
    }
}

// MARK: - Atoms

/// "✦ You fell asleep 12 min faster than usual." — one line of coaching on
/// frosted glass.
struct NekaInsightPill: View {
    let text: String
    let scene: Neka.Scene
    var icon: String = "sparkles"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(scene.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(scene.glass))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(scene.glassStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct NekaStat: Identifiable {
    let icon: String
    let label: String
    let value: String
    var id: String { label }
}

/// Three small stats across: icon + label over the value, pinned left,
/// center and right.
struct NekaStatRow: View {
    let stats: [NekaStat]
    let scene: Neka.Scene

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { i, stat in
                let edge = horizontal(i)
                VStack(alignment: edge, spacing: 4) {
                    Label(stat.label, systemImage: stat.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(scene.inkSecondary)
                        .lineLimit(1)
                    Text(stat.value)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(scene.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: edge, vertical: .top))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func horizontal(_ i: Int) -> HorizontalAlignment {
        if stats.count < 3 || i == 0 { return .leading }
        return i == stats.count - 1 ? .trailing : .center
    }
}

/// Full-width frosted white capsule — "Wind Down", "Add Glass".
struct NekaCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Color(hex: "1C1B22"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [.white, Color(hex: "EEEDF4")], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
            )
            .overlay(Capsule().stroke(Color.white, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NekaCapsuleButtonStyle {
    static var nekaCapsule: NekaCapsuleButtonStyle { NekaCapsuleButtonStyle() }
}

// MARK: - Dot charts

/// Columns of dots — a dot-matrix bar chart. Each column fills bottom-up
/// in proportion to its value; the last column is brightest.
struct NekaDotColumns: View {
    let values: [Double]
    var color: Color = Neka.ink
    var rows: Int = 8

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty, rows > 0 else { return }
            let hi = max(values.max() ?? 1, 0.0001)
            let colW = size.width / CGFloat(values.count)
            let rowH = size.height / CGFloat(rows)
            let dot = max(2, min(colW, rowH) * 0.5)
            for (i, v) in values.enumerated() {
                let lit = v > 0 ? max(1, Int((CGFloat(v / hi) * CGFloat(rows)).rounded())) : 0
                let x = colW * (CGFloat(i) + 0.5)
                for r in 0..<rows {
                    let y = size.height - rowH * (CGFloat(r) + 0.5)
                    let opacity: Double = r < lit ? (i == values.count - 1 ? 1 : 0.7) : 0.16
                    let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Water

/// Water in a glass: two slow waves at `progress` height with the percent
/// riding the waterline. Holds still with Reduce Motion on.
struct NekaWaterLevel: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let deep = Color(light: Color(hex: "7E9FE4"), dark: Color(hex: "2B4C8C"))
    private let shallow = Color(light: Color(hex: "A9C2F0"), dark: Color(hex: "3A63AE"))

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let level = CGFloat(min(1, max(0, progress)))
                let waterline = geo.size.height * (1 - level)
                ZStack(alignment: .topLeading) {
                    NekaWave(phase: phase * 1.1, amplitude: 7, level: level)
                        .fill(LinearGradient(colors: [shallow.opacity(0.95), deep], startPoint: .top, endPoint: .bottom))
                    NekaWave(phase: phase * 0.7 + 1.6, amplitude: 4, level: level)
                        .fill(Color.white.opacity(0.22))
                    Text("\(Int((min(progress, 9.99) * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Neka.surface.opacity(0.7)))
                        .position(x: geo.size.width - 46, y: max(18, waterline - 20))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(Int((min(progress, 9.99) * 100).rounded())) percent of goal")
    }
}

/// A filled sine wave whose rest line sits `level` of the way up.
struct NekaWave: Shape {
    var phase: Double
    var amplitude: CGFloat
    var level: CGFloat

    func path(in rect: CGRect) -> Path {
        let base = rect.height * (1 - level)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: base))
        for x in stride(from: CGFloat(0), through: rect.width, by: 4) {
            let angle = Double(x / max(rect.width, 1)) * .pi * 2.4 + phase
            path.addLine(to: CGPoint(x: x, y: base + amplitude * CGFloat(sin(angle))))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
