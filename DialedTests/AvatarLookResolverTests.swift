//
//  AvatarLookResolverTests.swift
//  DialedTests
//
//  A real photo wins over the drawing only when you've added one and photos
//  are on; framing crops stay inside the photo.
//

import XCTest
@testable import Dialed

final class AvatarLookResolverTests: XCTestCase {

    func testPhotoWinsOnlyWhenOn() {
        XCTAssertEqual(AvatarLookResolver.source(hasPhoto: true, hasGenerated: true, usePhotos: true), .photo)
        XCTAssertEqual(AvatarLookResolver.source(hasPhoto: true, hasGenerated: true, usePhotos: false), .generated)
        XCTAssertEqual(AvatarLookResolver.source(hasPhoto: true, hasGenerated: false, usePhotos: false), .none)
        XCTAssertEqual(AvatarLookResolver.source(hasPhoto: false, hasGenerated: true, usePhotos: true), .generated)
        XCTAssertEqual(AvatarLookResolver.source(hasPhoto: false, hasGenerated: false, usePhotos: true), .none)
        XCTAssertEqual(AvatarLookSource.photo.badge, "Photo")
        XCTAssertEqual(AvatarLookSource.generated.badge, "AI")
        XCTAssertNil(AvatarLookSource.none.badge)
    }

    func testAIDrawnFromPhotoShowsWhenChosen() {
        XCTAssertEqual(AvatarLookResolver.source(hasPhoto: true, hasGenerated: true, usePhotos: true, prefersDrawing: true), .generated)
        // Nothing drawn yet: the photo keeps showing.
        XCTAssertEqual(AvatarLookResolver.source(hasPhoto: true, hasGenerated: false, usePhotos: true, prefersDrawing: true), .photo)
    }

    func testCropIsAlwaysFourByFive() {
        // Tall photo: full width, centered.
        let whole = AvatarLookResolver.cropRect(width: 1000, height: 1500, framing: .init(cutout: false))
        XCTAssertEqual(whole.width, 1000)
        XCTAssertEqual(whole.height, 1250)
        XCTAssertEqual(whole.x, 0)
        XCTAssertEqual(whole.y, 125)

        // Wide photo: full height.
        let wide = AvatarLookResolver.cropRect(width: 2000, height: 1000, framing: .init(cutout: false))
        XCTAssertEqual(wide.width, 800)
        XCTAssertEqual(wide.height, 1000)
        XCTAssertEqual(wide.x, 600)

        let zoomed = AvatarLookResolver.cropRect(width: 1000, height: 1500, framing: .init(scale: 2, cutout: false))
        XCTAssertEqual(zoomed.width, 500)
        XCTAssertEqual(zoomed.height, 625)
        XCTAssertEqual(zoomed.x, 250)

        let topLeft = AvatarLookResolver.cropRect(width: 1000, height: 1500, framing: .init(scale: 2, offsetX: 1, offsetY: 1, cutout: false))
        XCTAssertEqual(topLeft.x, 0)
        XCTAssertEqual(topLeft.y, 0)
        let bottom = AvatarLookResolver.cropRect(width: 1000, height: 1500, framing: .init(scale: 2, offsetY: -1, cutout: false))
        XCTAssertEqual(bottom.y + bottom.height, 1500)

        // Out-of-range values are clamped; photos can't zoom out past filling.
        let wild = AvatarLookResolver.cropRect(width: 1000, height: 1250, framing: .init(scale: 9, offsetY: 5, cutout: false))
        XCTAssertEqual(wild.width, 250)
        XCTAssertEqual(wild.y, 0)
        let out = AvatarLookResolver.cropRect(width: 1000, height: 1250, framing: .init(scale: 0.2, cutout: false))
        XCTAssertEqual(out.width, 1000)
    }

    func testCutoutsStartWithHeadroomOnTheBottomEdge() {
        let f = AvatarLookResolver.defaultFraming(width: 600, height: 1500, cutout: true)
        let r = AvatarLookResolver.cropRect(width: 600, height: 1500, framing: f)
        // The whole cutout fits with room to spare, feet on the bottom edge.
        XCTAssertEqual(r.height, 1500 / 0.9, accuracy: 0.001)
        XCTAssertEqual(r.y + r.height, 1500, accuracy: 0.001)
        XCTAssertLessThan(r.y, 0)
        XCTAssertEqual(r.x + r.width / 2, 300, accuracy: 0.001)
    }

    func testCutoutsSlidePastTheirEdges() {
        // A cutout filling the frame top to bottom can still move down.
        let fit = AvatarLookResolver.Framing(scale: 1, offsetY: 1, cutout: true)
        let r = AvatarLookResolver.cropRect(width: 1000, height: 1250, framing: fit)
        XCTAssertEqual(r.y, -500, accuracy: 0.001)
        // Photos can't.
        let photo = AvatarLookResolver.cropRect(width: 1000, height: 1250, framing: .init(scale: 1, offsetY: 1, cutout: false))
        XCTAssertEqual(photo.y, 0)
        XCTAssertGreaterThan(AvatarLookResolver.offsetDelta(dragPoints: 10, image: 1250, crop: 1250, cutout: true,
                                                             cropWidth: 1000, shownWidth: 280), 0)
        XCTAssertEqual(AvatarLookResolver.offsetDelta(dragPoints: 10, image: 1250, crop: 1250, cutout: false,
                                                      cropWidth: 1000, shownWidth: 280), 0)
    }

    func testDragFollowsTheFinger() {
        // A 500 px-wide crop shown 250 pt wide: 1 pt = 2 px. 100 pt right
        // moves the crop 200 px left of a 500 px room → offset +0.8.
        let d = AvatarLookResolver.offsetDelta(dragPoints: 100, image: 1000, crop: 500, cutout: false,
                                               cropWidth: 500, shownWidth: 250)
        XCTAssertEqual(d, 0.8, accuracy: 0.0001)
    }

    func testOldFramingsStillDecode() throws {
        let old = #"{"scale":1.5,"offsetY":0.25,"cutout":false}"#.data(using: .utf8)!
        let f = try JSONDecoder().decode(AvatarLookResolver.Framing.self, from: old)
        XCTAssertEqual(f, .init(scale: 1.5, offsetX: 0, offsetY: 0.25, cutout: false))
    }
}
