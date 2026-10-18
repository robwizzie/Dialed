//
//  NekaTheme.swift
//  Dialed
//
//  The light, airy "Neka" visual language used by the Home and Challenge
//  tabs: warm off-white paper, frosted white cards, pastel gradient tiles,
//  near-black ink and generous type. Everything is an explicit color (no
//  `.primary`) so these screens look identical regardless of the system
//  appearance, and the legacy dark screens keep working beside them.
//

import SwiftUI

enum Neka {

    // MARK: - Ink & paper

    static let paper = Color(hex: "F3F3F0")
    static let paperDeep = Color(hex: "E9EAE6")
    static let card = Color.white.opacity(0.82)
    static let cardStroke = Color.black.opacity(0.05)

    static let ink = Color(hex: "121212")
    static let inkSecondary = Color(hex: "6E6E73")
    static let inkTertiary = Color(hex: "A1A1A6")
    static let hairline = Color.black.opacity(0.08)

    // MARK: - Accents

    static let green = Color(hex: "4CB868")
    static let greenSoft = Color(hex: "DDF3E1")
    static let orange = Color(hex: "F59A4C")
    static let orangeSoft = Color(hex: "FFE7D3")
    static let blue = Color(hex: "8BA3F7")
    static let blueSoft = Color(hex: "E3E9FF")
    static let sky = Color(hex: "5DB4F0")
    static let skySoft = Color(hex: "DDF0FC")
    static let rose = Color(hex: "EE7C8E")
    static let roseSoft = Color(hex: "FCE3E7")
    static let lavender = Color(hex: "A88BEB")
    static let lavenderSoft = Color(hex: "EDE5FC")
    static let amber = Color(hex: "F2C14E")
    static let amberSoft = Color(hex: "FFF4D6")

    /// The yellow dot used on the hero body callouts.
    static let pulse = Color(hex: "F4D35E")

    // MARK: - Tile washes

    /// Pastel washes for the metric tiles. Each is a soft top-left → bottom-
    /// right gradient that fades into white, like the reference design.
    enum Wash {
        case mint, peach, sky, rose, lavender, plain

        var colors: [Color] {
            switch self {
            case .mint:     return [Color(hex: "CFEFD4"), Color(hex: "EEF8E8"), Color.white.opacity(0.9)]
            case .peach:    return [Color(hex: "FFE1C7"), Color(hex: "FFF1DF"), Color.white.opacity(0.9)]
            case .sky:      return [Color(hex: "D4ECFB"), Color(hex: "ECF6FD"), Color.white.opacity(0.9)]
            case .rose:     return [Color(hex: "FBD9DF"), Color(hex: "FDEDEF"), Color.white.opacity(0.9)]
            case .lavender: return [Color(hex: "E4DAFB"), Color(hex: "F3EEFD"), Color.white.opacity(0.9)]
            case .plain:    return [Color.white.opacity(0.92), Color.white.opacity(0.8)]
            }
        }

        var gradient: LinearGradient {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
        )
    }

    /// Paper background with two faint radial glows so the page isn't flat.
    func nekaPageBackground() -> some View {
        background(
            ZStack {
                Neka.paper
                RadialGradient(
                    colors: [Color.white, Color.white.opacity(0)],
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

/// Section title used above cards ("Today's Timeline", "Coach").
struct NekaSectionTitle: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Neka.ink)
            Spacer()
            if let trailing { trailing }
        }
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
                Capsule().fill(Color.black.opacity(0.06))
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
            .foregroundColor(.white)
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
