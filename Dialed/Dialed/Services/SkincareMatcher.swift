//
//  SkincareMatcher.swift
//  Dialed
//
//  Skincare and face-wash tasks are gone from Dialed. This decides what
//  counts as one — by block kind, checklist type, or wording ("PM
//  skincare", "Wash face + CeraVe PM", "Sunscreen") — so the one-time
//  cleanup removes exactly those and nothing else. Pure Foundation, tested.
//

import Foundation

enum SkincareMatcher {

    /// Retired checklist types (Constants.ChecklistType raw values).
    static let checklistTypes: Set<String> = ["AM Skincare", "PM Skincare"]

    /// TemplateBlock / PlanBlock kind raw value.
    static let kind = "skincare"

    private static let phrases = [
        "skincare", "skin care", "skin-care", "face wash", "wash face", "wash your face", "facewash",
        "rinse face", "cleanser", "moisturizer", "moisturiser", "moisturize", "sunscreen", "cerave", "retinol"
    ]

    static func matches(_ text: String?) -> Bool {
        guard let t = text?.lowercased(), !t.isEmpty else { return false }
        if phrases.contains(where: t.contains) { return true }
        // "SPF 30" but not words that merely contain the letters.
        return t.range(of: #"\bspf\b"#, options: .regularExpression) != nil
    }

    /// A plan block or template block.
    static func isSkincare(kindRaw: String, title: String, detail: String? = nil) -> Bool {
        kindRaw == kind || matches(title) || matches(detail)
    }

    /// A checklist item (built-in type or custom task).
    static func isSkincare(checklistType: String, customTitle: String?, customDescription: String?) -> Bool {
        checklistTypes.contains(checklistType) || matches(customTitle) || matches(customDescription)
    }
}
