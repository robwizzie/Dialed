//
//  DialedStyle.swift
//  Dialed
//
//  Reusable SwiftUI view modifiers + button styles that lock the visual
//  language in one place. Every glass card, gradient CTA, and chip in
//  the redesign was duplicating the same RoundedRectangle/material/
//  stroke combo — this file is the consolidation.
//
//  Usage:
//      .dialedCard()                              // standard glass card
//      .dialedCard(cornerRadius: 18)              // custom corner
//      Button(...) { ... }
//          .buttonStyle(.dialedPrimary(.readiness))
//      Button(...) { ... }
//

import SwiftUI

// MARK: - Card surface

extension View {
    /// Standard glass card: nowCard fill + glassStroke border, 22pt
    /// corner radius. Override either via parameters.
    func dialedCard(
        cornerRadius: CGFloat = 22,
        fill: Color = AppColors.nowCard,
        strokeOpacity: Double = 1.0
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppColors.glassStroke.opacity(strokeOpacity), lineWidth: 0.5)
                )
        )
    }

    /// Lighter glass for inline / nested cards — uses ultraThinMaterial
    /// behind a lower-opacity stroke. Good for cards-within-cards.
    func dialedGlassCard(cornerRadius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppColors.glassStroke, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Buttons

/// The chunky gradient CTA — used for the primary action on capture
/// sheets, plan-block confirmations, etc. Pillar determines color.
struct DialedPrimaryButtonStyle: ButtonStyle {
    let pillar: AppColors.Pillar
    let cornerRadius: CGFloat

    init(_ pillar: AppColors.Pillar, cornerRadius: CGFloat = 18) {
        self.pillar = pillar
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: pillar.gradient,
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .shadow(
                        color: pillar.gradient.last!.opacity(configuration.isPressed ? 0.15 : 0.32),
                        radius: configuration.isPressed ? 8 : 16,
                        x: 0,
                        y: configuration.isPressed ? 3 : 8
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DialedPrimaryButtonStyle {
    static func dialedPrimary(_ pillar: AppColors.Pillar = .readiness,
                              cornerRadius: CGFloat = 18) -> DialedPrimaryButtonStyle {
        DialedPrimaryButtonStyle(pillar, cornerRadius: cornerRadius)
    }
}

// MARK: - Grabber

/// The drag handle at the top of every capture sheet. Was duplicated in
/// five sheets — consolidate.
struct GrabberHandle: View {
    var body: some View {
        Capsule()
            .fill(.white.opacity(0.15))
            .frame(width: 38, height: 4)
            .padding(.top, 10)
    }
}

// MARK: - Universal scale-on-press

/// Wraps any button label with a subtle press scale + spring. Use on
/// quick-add chips, FABs, and other buttons that don't get the gradient
/// CTA treatment. Pairs well with `.buttonStyle(.plain)` migrations —
/// just swap `.plain` for `.dialedScale`.
struct DialedScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DialedScaleButtonStyle {
    static var dialedScale: DialedScaleButtonStyle { DialedScaleButtonStyle() }
}

// MARK: - Section header

/// Small uppercased label used above sections on Now / Plan / Timeline /
/// Trends. Pinned in one place so the typography stays consistent.
struct DialedSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.4))
            .tracking(1.2)
    }
}

// MARK: - String convenience

extension String {
    /// Returns `fallback` when `self` is empty after trimming whitespace.
    /// Was duplicated as a fileprivate in two files — promote.
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespaces).isEmpty ? fallback : self
    }
}
