//
//  AppColors.swift
//  Dialed
//
//  App color scheme (OLED-friendly dark theme)
//

import SwiftUI

struct AppColors {
    // Background colors
    static let background = Color(hex: "0B0F14")
    static let surface = Color(hex: "111827")

    // Primary colors
    static let primary = Color(hex: "3B82F6")  // Electric blue
    static let success = Color(hex: "34D399")  // Mint green
    static let warning = Color(hex: "FBBF24")  // Amber
    static let danger = Color(hex: "F87171")   // Muted red

    // Text colors
    static let textPrimary = Color(hex: "E5E7EB")
    static let textSecondary = Color(hex: "94A3B8")

    // Score gradient colors
    static let scoreElite = Color(hex: "34D399")      // 90-100
    static let scoreStrong = Color(hex: "3B82F6")     // 75-89
    static let scoreDecent = Color(hex: "FBBF24")     // 60-74
    static let scoreSlipping = Color(hex: "FB923C")   // 40-59
    static let scoreReset = Color(hex: "F87171")      // 0-39

    static func scoreColor(for score: Int) -> Color {
        switch score {
        case 90...100:
            return scoreElite
        case 75..<90:
            return scoreStrong
        case 60..<75:
            return scoreDecent
        case 40..<60:
            return scoreSlipping
        default:
            return scoreReset
        }
    }

    static func scoreGrade(for score: Int) -> String {
        switch score {
        case 90...100:
            return "Elite"
        case 75..<90:
            return "Strong"
        case 60..<75:
            return "Decent"
        case 40..<60:
            return "Slipping"
        default:
            return "Reset"
        }
    }
}

// Helper extension for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
