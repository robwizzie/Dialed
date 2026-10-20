//
//  AvatarLookResolver.swift
//  Dialed
//
//  Each avatar look (a mood, or "future you") can be a real photo instead
//  of the generated drawing. This decides which one shows and how a photo
//  is framed (zoom + vertical slide, baked into the saved image so every
//  screen shows the same crop). Pure Foundation, unit-tested.
//

import Foundation

enum AvatarLookSource: Equatable {
    case photo
    case generated
    case none

    var badge: String? {
        switch self {
        case .photo:     return "Photo"
        case .generated: return "AI"
        case .none:      return nil
        }
    }
}

enum AvatarLookResolver {

    /// Your photo wins when you've added one and photos are switched on;
    /// otherwise the drawing, if there is one.
    static func source(hasPhoto: Bool, hasGenerated: Bool, usePhotos: Bool) -> AvatarLookSource {
        if hasPhoto && usePhotos { return .photo }
        if hasGenerated { return .generated }
        return .none
    }

    struct Framing: Codable, Equatable {
        /// 1 = whole photo, up to 2.5 = zoomed in.
        var scale: Double = 1
        /// −1…1: positive slides the crop up (shows more of the top).
        var offsetY: Double = 0
        /// Lift the person off the background.
        var cutout: Bool = true

        static let scaleRange = 1.0...2.5
        static let offsetRange = -1.0...1.0

        var clamped: Framing {
            Framing(scale: min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, scale)),
                    offsetY: min(Self.offsetRange.upperBound, max(Self.offsetRange.lowerBound, offsetY)),
                    cutout: cutout)
        }
    }

    /// The part of a `width` × `height` photo to keep: a centered crop
    /// shrunk by `scale`, slid vertically by `offsetY` of the room left,
    /// never past the photo's edges. Same aspect ratio as the photo.
    static func cropRect(width: Double, height: Double, framing: Framing) -> (x: Double, y: Double, width: Double, height: Double) {
        let f = framing.clamped
        let w = width / f.scale
        let h = height / f.scale
        let roomY = (height - h) / 2
        let x = (width - w) / 2
        let y = roomY - f.offsetY * roomY
        return (x, min(height - h, max(0, y)), w, h)
    }
}
