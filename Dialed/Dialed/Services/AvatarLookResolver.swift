//
//  AvatarLookResolver.swift
//  Dialed
//
//  Each avatar look (a mood, or "future you") can be a real photo instead
//  of the generated drawing. This decides which one shows and how a photo
//  is framed (a 4:5 crop you zoom and slide, baked into the saved image so
//  every screen shows the same crop). Pure Foundation, unit-tested.
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

    /// Your photo wins when you've added one and photos are switched on,
    /// unless you picked the AI look drawn from it; otherwise the drawing,
    /// if there is one.
    static func source(hasPhoto: Bool, hasGenerated: Bool, usePhotos: Bool,
                       prefersDrawing: Bool = false) -> AvatarLookSource {
        if hasPhoto && usePhotos && !(prefersDrawing && hasGenerated) { return .photo }
        if hasGenerated { return .generated }
        return .none
    }

    /// How a photo look is cropped. Every look is saved at one shape
    /// (`aspect`, 4:5) so the crop you set is the picture every screen
    /// shows.
    struct Framing: Codable, Equatable {
        /// 1 = the largest 4:5 crop that fits; higher zooms in. Cutouts can
        /// go below 1 to fit more of you (transparent around the edges).
        var scale: Double = 1
        /// −1…1: positive shows more of the left.
        var offsetX: Double = 0
        /// −1…1: positive shows more of the top.
        var offsetY: Double = 0
        /// Lift the person off the background.
        var cutout: Bool = true

        /// Width ÷ height of every saved photo look.
        static let aspect = 4.0 / 5.0
        static let maxScale = 4.0
        static let offsetRange = -1.0...1.0

        init(scale: Double = 1, offsetX: Double = 0, offsetY: Double = 0, cutout: Bool = true) {
            self.scale = scale
            self.offsetX = offsetX
            self.offsetY = offsetY
            self.cutout = cutout
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
            offsetX = try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
            offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
            cutout = try c.decodeIfPresent(Bool.self, forKey: .cutout) ?? true
        }

        /// Photos can't zoom out past filling the frame (no empty edges);
        /// cutouts can, to half size.
        var minScale: Double { cutout ? 0.5 : 1 }

        var clamped: Framing {
            func clamp(_ v: Double) -> Double { min(Self.offsetRange.upperBound, max(Self.offsetRange.lowerBound, v)) }
            return Framing(scale: min(Self.maxScale, max(minScale, scale)),
                           offsetX: clamp(offsetX), offsetY: clamp(offsetY), cutout: cutout)
        }
    }

    /// The part of a `width` × `height` image to keep, always 4:5: the
    /// largest 4:5 rect that fits, divided by `scale`, slid by the offsets.
    /// Photos slide only as far as their edges (no empty strips); cutouts
    /// are transparent around you, so they can slide past theirs — e.g. to
    /// leave room above your head.
    static func cropRect(width: Double, height: Double, framing: Framing) -> (x: Double, y: Double, width: Double, height: Double) {
        let f = framing.clamped
        let (w, h) = cropSize(width: width, height: height, scale: f.scale)
        let sx = slide(image: width, crop: w, cutout: f.cutout)
        let sy = slide(image: height, crop: h, cutout: f.cutout)
        return (sx.hi - (sx.hi - sx.lo) * (1 + f.offsetX) / 2,
                sy.hi - (sy.hi - sy.lo) * (1 + f.offsetY) / 2, w, h)
    }

    private static func cropSize(width: Double, height: Double, scale: Double) -> (Double, Double) {
        let fill = width / height > Framing.aspect
            ? (w: height * Framing.aspect, h: height)
            : (w: width, h: width / Framing.aspect)
        return (fill.w / scale, fill.h / scale)
    }

    /// Where the crop's edge can sit along one axis (image coordinates).
    static func slide(image: Double, crop: Double, cutout: Bool) -> (lo: Double, hi: Double) {
        let room = image - crop
        let slack = cutout ? crop * 0.4 : 0
        return (min(0, room) - slack, max(0, room) + slack)
    }

    /// How much one point of drag moves an offset along an axis, for a crop
    /// shown `shownWidth` points wide: the picture follows your finger.
    static func offsetDelta(dragPoints: Double, image: Double, crop: Double, cutout: Bool,
                            cropWidth: Double, shownWidth: Double) -> Double {
        let s = slide(image: image, crop: crop, cutout: cutout)
        let span = s.hi - s.lo
        guard span > 0.5, shownWidth > 0 else { return 0 }
        return 2 * dragPoints * (cropWidth / shownWidth) / span
    }

    /// Where a new photo starts: photos fill the frame, centered; cutouts
    /// fit whole with a little room above the head, standing on the
    /// bottom edge.
    static func defaultFraming(width: Double, height: Double, cutout: Bool) -> Framing {
        guard cutout else { return Framing(cutout: false) }
        let (fw, fh) = cropSize(width: width, height: height, scale: 1)
        let scale = max(0.5, min(fw / width, fh / height) * 0.9)
        let (w, h) = cropSize(width: width, height: height, scale: scale)
        func offset(_ edge: Double, _ s: (lo: Double, hi: Double)) -> Double {
            s.hi - s.lo > 0.5 ? 2 * (s.hi - edge) / (s.hi - s.lo) - 1 : 0
        }
        let sx = slide(image: width, crop: w, cutout: true)
        let sy = slide(image: height, crop: h, cutout: true)
        return Framing(scale: scale,
                       offsetX: offset((width - w) / 2, sx),
                       offsetY: offset(height - h, sy),
                       cutout: true).clamped
    }
}
