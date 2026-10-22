//
//  FocusedImage.swift
//  Dialed
//
//  Fills its frame with an image, framed on the face instead of the
//  middle. Avatars from Image Playground often put the person off to one
//  side, so a plain center crop cuts them off or leaves them in a corner.
//
//  Real photo looks are different: you already cropped them, so they're
//  laid out by `PhotoLookFill` — the same layout the crop editor previews
//  with — and never re-aimed at a face.
//

import SwiftUI

struct FocusedImage: View {
    let image: UIImage
    /// Where the face should land in the frame, as a fraction of its height.
    var anchorY: CGFloat = 0.4
    /// Extra zoom past "fill" so there's room to slide toward the face.
    var zoom: CGFloat = 1.12

    @ObservedObject private var studio = AvatarStudio.shared

    var body: some View {
        if studio.isPhotoLook(image) {
            PhotoLookFill(aspect: image.size.width / max(1, image.size.height)) {
                Image(uiImage: image).resizable()
            }
        } else {
            drawing
        }
    }

    private var drawing: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let iw = max(1, image.size.width)
            let ih = max(1, image.size.height)
            let focus = studio.focus(of: image)
            // Without a detected face, fill and center as before.
            let scale = max(w / iw, h / ih) * (focus == nil ? 1 : zoom)
            let dw = iw * scale
            let dh = ih * scale
            let f = focus ?? CGPoint(x: 0.5, y: 0.5)
            let target = focus == nil ? CGPoint(x: w / 2, y: h / 2) : CGPoint(x: w / 2, y: h * anchorY)
            // Slide the face to the target, without exposing an edge.
            let x0 = min(0, max(w - dw, target.x - f.x * dw))
            let y0 = min(0, max(h - dh, target.y - f.y * dh))

            Image(uiImage: image)
                .resizable()
                .frame(width: dw, height: dh)
                .position(x: x0 + dw / 2, y: y0 + dh / 2)
                .animation(.easeOut(duration: 0.25), value: focus == nil)
        }
        .clipped()
    }
}

/// Fills a frame of any shape with a photo look (`aspect` wide ÷ tall):
/// centered across, and when the frame is wider than the look, trimming
/// mostly from the bottom so heads stay in.
struct PhotoLookFill<Content: View>: View {
    var aspect: CGFloat = AvatarLookResolver.Framing.aspect
    @ViewBuilder var content: Content

    /// Share of the overflow trimmed from the top.
    static var topTrim: CGFloat { 0.3 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let wide = w / max(1, h) > aspect
            let dw = wide ? w : h * aspect
            let dh = wide ? w / aspect : h
            content
                .frame(width: dw, height: dh)
                .position(x: w / 2, y: (h - dh) * Self.topTrim + dh / 2)
        }
        .clipped()
    }
}

/// `base` cropped by `framing`, drawn live into a 4:5 frame — exactly what
/// AvatarStudio.framed bakes, so the editor shows the saved result.
struct PhotoCropView: View {
    let base: UIImage
    let framing: AvatarLookResolver.Framing

    var body: some View {
        GeometryReader { geo in
            let iw = Double(base.size.width)
            let ih = Double(base.size.height)
            let r = AvatarLookResolver.cropRect(width: iw, height: ih, framing: framing)
            let k = geo.size.width / r.width
            Image(uiImage: base)
                .resizable()
                .frame(width: iw * k, height: ih * k)
                .position(x: (-r.x + iw / 2) * k, y: (-r.y + ih / 2) * k)
        }
        .aspectRatio(AvatarLookResolver.Framing.aspect, contentMode: .fit)
        .clipped()
    }
}
