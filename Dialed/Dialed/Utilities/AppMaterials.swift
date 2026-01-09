//
//  AppMaterials.swift
//  Dialed
//
//  Apple's liquid glass design system - materials, vibrancy, depth
//

import SwiftUI

struct AppMaterials {
    // MARK: - Backgrounds (Materials)

    /// Primary background material for cards and containers
    static let cardBackground = Material.ultraThinMaterial

    /// Secondary background for nested elements
    static let surfaceBackground = Material.thinMaterial

    /// Elevated surface (floating elements)
    static let elevatedBackground = Material.regularMaterial

    // MARK: - Glass Effects

    /// Glass card modifier with blur and vibrancy
    struct GlassCard: ViewModifier {
        let cornerRadius: CGFloat
        let padding: CGFloat

        init(cornerRadius: CGFloat = 16, padding: CGFloat = 16) {
            self.cornerRadius = cornerRadius
            self.padding = padding
        }

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
        }
    }

    /// Elevated glass card with stronger shadow
    struct ElevatedGlassCard: ViewModifier {
        let cornerRadius: CGFloat
        let padding: CGFloat

        init(cornerRadius: CGFloat = 16, padding: CGFloat = 16) {
            self.cornerRadius = cornerRadius
            self.padding = padding
        }

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.regularMaterial)

                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                )
        }
    }

    /// Subtle glass effect for progress bars
    struct GlassProgress: ViewModifier {
        let cornerRadius: CGFloat

        init(cornerRadius: CGFloat = 10) {
            self.cornerRadius = cornerRadius
        }

        func body(content: Content) -> some View {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.thickMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(.white.opacity(0.15), lineWidth: 0.5)
                        )
                )
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply glass card style
    func glassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(AppMaterials.GlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    /// Apply elevated glass card style
    func elevatedGlassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(AppMaterials.ElevatedGlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    /// Apply glass progress style
    func glassProgress(cornerRadius: CGFloat = 10) -> some View {
        modifier(AppMaterials.GlassProgress(cornerRadius: cornerRadius))
    }
}

// MARK: - Color Extensions for Vibrancy

extension Color {
    /// Primary text with vibrancy
    static let vibrantPrimary = Color.primary

    /// Secondary text with vibrancy
    static let vibrantSecondary = Color.secondary

    /// Adaptive colors that work with materials
    static let adaptiveAccent = Color.blue
    static let adaptiveSuccess = Color.green
    static let adaptiveWarning = Color.orange
    static let adaptiveDanger = Color.red
}
