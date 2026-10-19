//
//  FocusedImage.swift
//  Dialed
//
//  Fills its frame with an image, framed on the face instead of the
//  middle. Avatars from Image Playground often put the person off to one
//  side, so a plain center crop cuts them off or leaves them in a corner.
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
