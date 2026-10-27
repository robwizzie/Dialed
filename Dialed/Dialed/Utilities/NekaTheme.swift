//
//  NekaTheme.swift
//  Dialed
//
//  The airy "Neka" visual language used by the Home and Challenge tabs:
//  warm paper, frosted cards, pastel gradient tiles, high-contrast ink
//  and generous type. Every token is a light/dark pair resolved from the
//  current color scheme, so these screens follow the system appearance
//  while the legacy dark screens keep working beside them.
//

import SwiftUI
import UIKit

extension Color {
    /// A color that resolves to `light` or `dark` with the color scheme.
    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

enum Neka {

    // MARK: - Ink & paper

    static let paper = Color(light: Color(hex: "F3F3F0"), dark: Color(hex: "0E0F11"))
    static let paperDeep = Color(light: Color(hex: "E9EAE6"), dark: Color(hex: "1A1C20"))
    /// Raised surface — cards, chips, buttons.
    static let surface = Color(light: .white, dark: Color(hex: "1E2125"))
    /// Highlight used for glows and card rims.
    static let glow = Color(light: .white, dark: Color.white.opacity(0.06))
    static let card = surface.opacity(0.82)
    static let cardStroke = Color(light: Color.white.opacity(0.9), dark: Color.white.opacity(0.07))

    static let ink = Color(light: Color(hex: "121212"), dark: Color(hex: "F4F4F2"))
    /// Text/icon color on top of an `ink` fill.
    static let onInk = Color(light: .white, dark: Color(hex: "0E0F11"))
    static let inkSecondary = Color(light: Color(hex: "6E6E73"), dark: Color(hex: "A0A0A6"))
    /// Captions and footnotes — still ≥ 3.5:1 on cards so small text reads.
    static let inkTertiary = Color(light: Color(hex: "7F7F85"), dark: Color(hex: "8E8E95"))
    static let hairline = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.1))
    /// Neutral track behind bars and rings.
    static let track = Color(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.09))
    /// Inactive bars and grabbers.
    static let muted = Color(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.18))
    static let shadow = Color(light: Color.black.opacity(0.05), dark: Color.black.opacity(0.25))

    // MARK: - Accents

    static let green = Color(hex: "4CB868")
    static let greenSoft = Color(light: Color(hex: "DDF3E1"), dark: Color(hex: "1C3324"))
    static let orange = Color(hex: "F59A4C")
    static let orangeSoft = Color(light: Color(hex: "FFE7D3"), dark: Color(hex: "3A2718"))
    static let blue = Color(hex: "8BA3F7")
    static let blueSoft = Color(light: Color(hex: "E3E9FF"), dark: Color(hex: "1F2640"))
    static let sky = Color(hex: "5DB4F0")
    static let skySoft = Color(light: Color(hex: "DDF0FC"), dark: Color(hex: "16293A"))
    static let rose = Color(hex: "EE7C8E")
    static let roseSoft = Color(light: Color(hex: "FCE3E7"), dark: Color(hex: "3A1C22"))
    static let lavender = Color(hex: "A88BEB")
    static let lavenderSoft = Color(light: Color(hex: "EDE5FC"), dark: Color(hex: "29203D"))
    static let amber = Color(hex: "F2C14E")
    static let amberSoft = Color(light: Color(hex: "FFF4D6"), dark: Color(hex: "3A3018"))

    // MARK: - Accent text

    /// Deeper accents for small colored text (status lines, chips). The
    /// accents above are tuned for fills and wash out as 11pt text on the
    /// pastel cards.
    static let greenText = Color(light: Color(hex: "2B7F45"), dark: Color(hex: "7DD89A"))
    static let orangeText = Color(light: Color(hex: "B85A12"), dark: Color(hex: "FFB57A"))
    static let skyText = Color(light: Color(hex: "1B6FA8"), dark: Color(hex: "8CCBF7"))
    static let roseText = Color(light: Color(hex: "B8334B"), dark: Color(hex: "F59BAA"))
    static let lavenderText = Color(light: Color(hex: "6A4BC4"), dark: Color(hex: "C4AEF5"))

    /// The yellow dot used on the hero body callouts.
    static let pulse = Color(hex: "F4D35E")

    /// Apple Intelligence-style iridescent stops for AI surfaces.
    static let intelligence: [Color] = [
        Color(hex: "F5A35C"), Color(hex: "EE7C8E"), Color(hex: "B98CF0"),
        Color(hex: "6FA8F7"), Color(hex: "5FD3C4"), Color(hex: "F5A35C")
    ]

    // MARK: - Tile washes

    /// Pastel washes for the metric tiles: a soft top-left → bottom-right
    /// gradient that fades into the card color. Deep tinted glass in dark.
    enum Wash {
        case mint, peach, sky, rose, lavender, plain
        /// Saturated, edge-to-edge tints for headline tiles.
        case lime, amber, ice, violet, blush

        var colors: [Color] {
            switch self {
            case .lime:     return Self.vivid("C4EFB4", "E6F7A6", dark: "26431F", "18291A")
            case .amber:    return Self.vivid("FFC66E", "FFE2A0", dark: "4A3416", "2C2114")
            case .ice:      return Self.vivid("B4C9F0", "DCE6F8", dark: "1C3150", "151F30")
            case .violet:   return Self.vivid("9A6CF5", "6F3BEB", dark: "4B2A9E", "2E1A63")
            case .blush:    return Self.vivid("FFC0CB", "FFE0D4", dark: "4A2129", "2C181C")
            case .mint:     return Self.pair("CFEFD4", "EEF8E8", dark: "1D3A27", "17241C")
            case .peach:    return Self.pair("FFE1C7", "FFF1DF", dark: "3D2A1A", "261E17")
            case .sky:      return Self.pair("D4ECFB", "ECF6FD", dark: "17324A", "16212C")
            case .rose:     return Self.pair("FBD9DF", "FDEDEF", dark: "40212A", "28191D")
            case .lavender: return Self.pair("E4DAFB", "F3EEFD", dark: "2E2445", "1F1A2B")
            case .plain:    return [Neka.surface.opacity(0.92), Neka.surface.opacity(0.8)]
            }
        }

        private static func pair(_ l1: String, _ l2: String, dark d1: String, _ d2: String) -> [Color] {
            [
                Color(light: Color(hex: l1), dark: Color(hex: d1)),
                Color(light: Color(hex: l2), dark: Color(hex: d2)),
                Neka.surface.opacity(0.9)
            ]
        }

        private static func vivid(_ l1: String, _ l2: String, dark d1: String, _ d2: String) -> [Color] {
            [Color(light: Color(hex: l1), dark: Color(hex: d1)), Color(light: Color(hex: l2), dark: Color(hex: d2))]
        }

        var isVivid: Bool {
            switch self {
            case .lime, .amber, .ice, .violet, .blush: return true
            default: return false
            }
        }

        /// Text drawn on the wash.
        var ink: Color { self == .violet ? .white : Neka.ink }
        var inkSecondary: Color { self == .violet ? Color.white.opacity(0.75) : Neka.inkSecondary }

        var gradient: LinearGradient {
            isVivid
                ? LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - Type

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let title = Font.system(size: 15, weight: .semibold)
    static let label = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)

    // MARK: - Radii

    static let heroRadius: CGFloat = 34
    static let cardRadius: CGFloat = 26
    static let tileRadius: CGFloat = 24
}

// MARK: - Card surfaces

extension View {
    /// Frosted white card with a hairline stroke and a soft drop shadow.
    func nekaCard(cornerRadius: CGFloat = Neka.cardRadius, wash: Neka.Wash = .plain) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(wash.gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Neka.cardStroke, lineWidth: 1)
                )
                .shadow(color: Neka.shadow, radius: 8, x: 0, y: 4)
        )
    }

    /// Solid band behind the status bar so scrolled content doesn't run
    /// into the clock and battery on screens with a hidden nav bar.
    /// Pass the scene's `top` on screens with a color wash.
    func nekaStatusBarScrim(_ color: Color = Neka.paper) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(color.opacity(0.96))
        }
    }

    /// Paper background with two faint radial glows so the page isn't flat.
    func nekaPageBackground() -> some View {
        background(
            ZStack {
                Neka.paper
                RadialGradient(
                    colors: [Neka.glow, Neka.glow.opacity(0)],
                    center: .topLeading, startRadius: 10, endRadius: 420
                )
                RadialGradient(
                    colors: [Neka.greenSoft.opacity(0.55), Color.clear],
                    center: .bottomTrailing, startRadius: 20, endRadius: 520
                )
            }
            .ignoresSafeArea()
        )
    }
}

// MARK: - Shared atoms

/// Tile header: title on the left, ↗ on the right.
struct NekaTileHeader: View {
    let title: String
    var showsArrow: Bool = true

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(Neka.label)
                .foregroundColor(Neka.ink)
            Spacer(minLength: 4)
            if showsArrow {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
    }
}

/// Big number + unit, baseline aligned.
struct NekaValue: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 36

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(Neka.display(size, weight: .medium))
                .foregroundColor(Neka.ink)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let unit {
                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
    }
}

/// Small rounded pill — "−6 years" style.
struct NekaPill: View {
    let text: String
    var tint: Color = Neka.green
    var fill: Color = Neka.greenSoft

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }
}

/// Pastel circular icon used in insight rows and device rows.
struct NekaIconBadge: View {
    let systemName: String
    var tint: Color
    var fill: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
    }
}

/// Thin progress bar with a rounded track.
struct NekaProgressBar: View {
    let progress: Double
    var tint: Color = Neka.green
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Neka.track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
    }
}

/// Dark primary button (the "Upgrade"/CTA look).
struct NekaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Neka.onInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Neka.ink)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NekaPrimaryButtonStyle {
    static var nekaPrimary: NekaPrimaryButtonStyle { NekaPrimaryButtonStyle() }
}
