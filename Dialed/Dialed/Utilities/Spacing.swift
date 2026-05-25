//
//  Spacing.swift
//  Dialed
//
//  Single source of truth for spacing. Adopt these tokens in views
//  instead of hardcoded literals so layout rhythm stays consistent.
//

import Foundation

struct Spacing {
    // Raw scale (use semantic tokens below in views — these are the
    // building blocks)
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 40
    static let xxxl: CGFloat = 48

    // Semantic tokens — prefer these in views.
    static let cardPadding: CGFloat = md            // 16 — internal padding of a card
    static let sectionSpacing: CGFloat = lg         // 24 — gap between sections on a screen
    static let screenPadding: CGFloat = md          // 16 — horizontal screen edge padding
    static let componentSpacing: CGFloat = sm       // 12 — gap between siblings inside a card

    // 2.0 additions
    static let heroCardRadius: CGFloat = 28         // four-ring grid cells
    static let cardRadius: CGFloat = 22             // standard glass card
    static let tertiaryCardRadius: CGFloat = 18     // chips, small tiles
    static let inputRadius: CGFloat = 14            // text fields, sliders
}
