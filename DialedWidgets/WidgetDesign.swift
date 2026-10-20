//
//  WidgetDesign.swift
//  DialedWidgets
//
//  The app's Neka look, rebuilt for widgets (the app's theme files aren't
//  compiled into this target): warm paper, pastel washes, high-contrast
//  ink, plus the small pieces every widget is made of — rings, bars,
//  week charts, a sparkline, the water bottle and tap-to-log chips.
//

import SwiftUI
import WidgetKit

// MARK: - Palette (mirrors Neka in Utilities/NekaTheme.swift)

enum Theme {
    static let paper = Color(light: 0xF3F3F0, dark: 0x0E0F11)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1E2125)
    static let ink = Color(light: 0x121212, dark: 0xF4F4F2)
    static let inkSecondary = Color(light: 0x6E6E73, dark: 0xA0A0A6)
    static let inkTertiary = Color(light: 0x7F7F85, dark: 0x8E8E95)
    static let track = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.1) : UIColor.black.withAlphaComponent(0.07) })
    static let chip = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.7) })

    static let green = Color(hex: 0x4CB868)
    static let orange = Color(hex: 0xF59A4C)
    static let blue = Color(hex: 0x8BA3F7)
    static let sky = Color(hex: 0x5DB4F0)
    static let rose = Color(hex: 0xEE7C8E)
    static let lavender = Color(hex: 0xA88BEB)
    static let amber = Color(hex: 0xF2C14E)

    static let greenSoft = Color(light: 0xDDF3E1, dark: 0x1C3324)
    static let orangeSoft = Color(light: 0xFFE7D3, dark: 0x3A2718)
    static let skySoft = Color(light: 0xDDF0FC, dark: 0x16293A)
    static let roseSoft = Color(light: 0xFCE3E7, dark: 0x3A1C22)
    static let lavenderSoft = Color(light: 0xEDE5FC, dark: 0x29203D)
    static let amberSoft = Color(light: 0xFFF4D6, dark: 0x3A3018)

    /// Deeper accents for small colored text on the pastel washes.
    static let greenText = Color(light: 0x2B7F45, dark: 0x7DD89A)
    static let orangeText = Color(light: 0xB85A12, dark: 0xFFB57A)
    static let skyText = Color(light: 0x1B6FA8, dark: 0x8CCBF7)
    static let roseText = Color(light: 0xB8334B, dark: 0xF59BAA)
    static let lavenderText = Color(light: 0x6A4BC4, dark: 0xC4AEF5)

    // Pillars, so every widget colors the same metric the same way.
    static let water = sky
    static let protein = green
    static let calories = orange

    /// Pastel tile washes — soft top-left → bottom-right, deep tinted glass in dark.
    enum Wash {
        case paper, mint, peach, sky, rose, lavender, amber

        var colors: [Color] {
            switch self {
            case .paper:    return [Color(light: 0xFAFAF8, dark: 0x1A1C20), Color(light: 0xF0F1EC, dark: 0x111215)]
            case .mint:     return [Color(light: 0xCFEFD4, dark: 0x1D3A27), Color(light: 0xF4FAF0, dark: 0x141B17)]
            case .peach:    return [Color(light: 0xFFE1C7, dark: 0x3D2A1A), Color(light: 0xFFF6EC, dark: 0x1B1714)]
            case .sky:      return [Color(light: 0xD4ECFB, dark: 0x17324A), Color(light: 0xF2F9FE, dark: 0x13191F)]
            case .rose:     return [Color(light: 0xFBD9DF, dark: 0x40212A), Color(light: 0xFEF2F4, dark: 0x1C1517)]
            case .lavender: return [Color(light: 0xE4DAFB, dark: 0x2E2445), Color(light: 0xF7F3FE, dark: 0x18161F)]
            case .amber:    return [Color(light: 0xFFEDBF, dark: 0x3A3018), Color(light: 0xFFF9EA, dark: 0x1B1913)]
            }
        }

        /// Matching flat fill for tiles that sit on a paper background.
        var tile: Color { colors[0].opacity(0.75) }
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static let caption = Font.system(size: 11, weight: .medium)
    static let micro = Font.system(size: 9.5, weight: .semibold)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    /// "4CB868" → color; the mood accent arrives as hex from the app.
    init(hexString: String) {
        self.init(hex: UInt32(hexString, radix: 16) ?? 0x4CB868)
    }
}

// MARK: - Backgrounds

struct WashBackground: View {
    let wash: Theme.Wash

    var body: some View {
        ZStack {
            LinearGradient(colors: wash.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [Color.white.opacity(0.35), .clear],
                center: .topLeading, startRadius: 4, endRadius: 220
            )
            .blendMode(.softLight)
        }
    }
}

extension View {
    /// Neka wash behind the widget (dropped automatically in tinted/clear modes).
    func dialedBackground(_ wash: Theme.Wash) -> some View {
        containerBackground(for: .widget) { WashBackground(wash: wash) }
    }

    /// Rounded tile on top of a widget background.
    func widgetTile(_ fill: Color, radius: CGFloat = 16) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }
}

// MARK: - Text atoms

/// Icon + title in the top-left of a widget, optional trailing caption.
struct WidgetTitle: View {
    let icon: String
    let title: String
    var tint: Color = Theme.green
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let trailing {
                Text(trailing)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Big number + unit, baseline aligned (NekaValue).
struct ValueText: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 28
    var unitColor: Color = Theme.inkSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(Theme.display(size, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let unit {
                Text(unit)
                    .font(.system(size: max(9, size * 0.4), weight: .semibold))
                    .foregroundStyle(unitColor)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Rings

/// Progress ring with a soft angular gradient and an optional "pace" tick
/// showing where you should be by now.
struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 8
    var pace: Double? = nil

    var body: some View {
        let p = max(0, min(1, progress))
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: p)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.65), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(0.05, p))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
                .opacity(p > 0 ? 1 : 0)
            if let pace, pace > 0, pace < 1 {
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.ink.opacity(0.55))
                        .frame(width: 2, height: lineWidth + 3)
                        .position(x: geo.size.width / 2, y: 0)
                        .rotationEffect(.degrees(360 * pace))
                }
            }
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Bars & charts

/// Thin capsule bar with an optional pace tick.
struct CapsuleBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 6
    var pace: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let p = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: p > 0 ? max(height, geo.size.width * p) : 0)
                    .widgetAccentable()
                if let pace, pace > 0, pace < 1 {
                    Capsule()
                        .fill(Theme.ink.opacity(0.5))
                        .frame(width: 2, height: height + 4)
                        .offset(x: geo.size.width * pace - 1)
                }
            }
        }
        .frame(height: height)
    }
}

/// Seven days of bars (oldest → today), with an optional dashed goal line.
struct WeekBars: View {
    let values: [Double]
    let tint: Color
    var goal: Double? = nil
    var showsDays = true
    var today: Date = Date()

    var body: some View {
        let days = Array(values.suffix(7))
        let top = max(days.max() ?? 0, goal ?? 0, 1)
        VStack(spacing: 3) {
            GeometryReader { geo in
                let slot = geo.size.width / CGFloat(max(days.count, 1))
                let barWidth = min(slot * 0.5, 10)
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.offset) { index, value in
                            let isToday = index == days.count - 1
                            let hit = goal.map { value >= $0 } ?? false
                            RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                                .fill(isToday || hit ? tint : tint.opacity(0.35))
                                .frame(width: barWidth, height: max(barWidth, geo.size.height * value / top))
                                .frame(maxWidth: .infinity)
                                .widgetAccentable(isToday)
                        }
                    }
                    if let goal, goal > 0 {
                        Path { path in
                            let y = geo.size.height * (1 - goal / top)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Theme.inkSecondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                }
            }
            if showsDays {
                HStack(spacing: 0) {
                    ForEach(Array(dayLetters(count: days.count).enumerated()), id: \.offset) { index, letter in
                        Text(letter)
                            .font(.system(size: 8.5, weight: index == days.count - 1 ? .bold : .medium))
                            .foregroundStyle(index == days.count - 1 ? Theme.ink : Theme.inkTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func dayLetters(count: Int) -> [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let day = WidgetBridge.logicalDay(for: today)
        return (0..<count).reversed().map { back in
            let date = calendar.date(byAdding: .day, value: -back, to: day) ?? day
            return symbols[calendar.component(.weekday, from: date) - 1]
        }
    }
}

/// Line + soft area fill, with a dot on the latest value.
struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            if points.count > 1 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(Theme.surface, lineWidth: 1.5))
                        .frame(width: 6, height: 6)
                        .position(points.last!)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let span = max(hi - lo, 0.5)
        let inset: CGFloat = 4
        return values.enumerated().map { index, value in
            CGPoint(
                x: inset + (size.width - inset * 2) * CGFloat(index) / CGFloat(values.count - 1),
                y: inset + (size.height - inset * 2) * CGFloat(1 - (value - lo) / span)
            )
        }
    }
}

// MARK: - Water bottle

/// A bottle that fills with a wavy waterline.
struct WaterBottle: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let glass = RoundedRectangle(cornerRadius: w * 0.3, style: .continuous)
            VStack(spacing: h * 0.025) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.sky.opacity(0.85))
                    .frame(width: w * 0.42, height: h * 0.08)
                    .widgetAccentable()
                ZStack {
                    glass.fill(Theme.track)
                    Wave(level: progress, amplitude: h * 0.025)
                        .fill(LinearGradient(
                            colors: [Color(hex: 0x8CD0FA), Theme.sky, Color(hex: 0x3D8FD6)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .widgetAccentable()
                    if progress > 0.2 {
                        bubbles(width: w, height: h * 0.9)
                    }
                    // Shine on the glass.
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: w * 0.08, height: h * 0.38)
                        .offset(x: -w * 0.26, y: -h * 0.12)
                    glass.stroke(Theme.sky.opacity(0.4), lineWidth: 1.5)
                }
                .clipShape(glass)
            }
        }
    }

    private func bubbles(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack {
            Circle().fill(.white.opacity(0.45)).frame(width: w * 0.12).offset(x: w * 0.12, y: h * 0.3)
            Circle().fill(.white.opacity(0.35)).frame(width: w * 0.08).offset(x: -w * 0.08, y: h * 0.18)
            Circle().fill(.white.opacity(0.3)).frame(width: w * 0.06).offset(x: w * 0.2, y: h * 0.1)
        }
    }
}

private struct Wave: Shape {
    let level: Double
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let fill = max(0, min(1, level))
        guard fill > 0 else { return path }
        let y = rect.maxY - rect.height * fill + (fill >= 1 ? -amplitude : 0)
        path.move(to: CGPoint(x: rect.minX, y: y))
        let steps = 24
        for i in 0...steps {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
            let angle = Double(i) / Double(steps) * .pi * 3
            path.addLine(to: CGPoint(x: x, y: y + amplitude * CGFloat(sin(angle))))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Chips

/// The tap-to-log capsule used for widget buttons.
struct ActionChip: View {
    let icon: String
    let text: String
    var tint: Color = Theme.ink
    var fill: Color = Theme.chip
    var height: CGFloat = 30

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Capsule().fill(fill))
    }
}

/// Little colored status capsule ("On pace", "Day 18").
struct StatusPill: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.greenText
    var fill: Color = Theme.greenSoft

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(fill))
    }
}

/// "Open Dialed to sync" stand-in for data the app hasn't published yet.
struct SyncHint: View {
    var text = "Open Dialed to sync"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(text)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Theme.inkSecondary)
    }
}

// MARK: - Avatar

/// Today's mood avatar, or the mood emoji when there isn't one.
struct MoodFace: View {
    let avatar: UIImage?
    let emoji: String
    let accent: Color
    var size: CGFloat

    var body: some View {
        Group {
            if let avatar {
                avatarImage(avatar)
            } else {
                Text(emoji)
                    .font(.system(size: size * 0.52))
                    .frame(width: size, height: size)
                    .background(Circle().fill(accent.opacity(0.18)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.surface.opacity(0.9), lineWidth: 2))
    }

    @ViewBuilder
    private func avatarImage(_ image: UIImage) -> some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: image).resizable().widgetAccentedRenderingMode(.desaturated).scaledToFill()
        } else {
            Image(uiImage: image).resizable().scaledToFill()
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static func int(_ value: Double) -> String { Int(value.rounded()).formatted() }

    /// 7420 → "7.4k"
    static func compact(_ value: Int) -> String {
        value >= 10_000 ? "\(value / 1000)k"
            : value >= 1_000 ? String(format: "%.1fk", Double(value) / 1000)
            : "\(value)"
    }

    static func hours(_ value: Double) -> String {
        let h = Int(value)
        let m = Int(((value - Double(h)) * 60).rounded())
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func signed(_ value: Double, digits: Int = 1) -> String {
        let s = String(format: "%.\(digits)f", abs(value))
        return value < 0 ? "−\(s)" : "+\(s)"
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased()
    }
}
