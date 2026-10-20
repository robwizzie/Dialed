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

    func testCropStaysInsideThePhoto() {
        let whole = AvatarLookResolver.cropRect(width: 1000, height: 1500, framing: .init())
        XCTAssertEqual(whole.x, 0)
        XCTAssertEqual(whole.y, 0)
        XCTAssertEqual(whole.width, 1000)
        XCTAssertEqual(whole.height, 1500)

        let zoomed = AvatarLookResolver.cropRect(width: 1000, height: 1500, framing: .init(scale: 2, offsetY: 0))
        XCTAssertEqual(zoomed.width, 500)
        XCTAssertEqual(zoomed.height, 750)
        XCTAssertEqual(zoomed.x, 250)
        XCTAssertEqual(zoomed.y, 375)

        let top = AvatarLookResolver.cropRect(width: 1000, height: 1500, framing: .init(scale: 2, offsetY: 1))
        XCTAssertEqual(top.y, 0)
        let bottom = AvatarLookResolver.cropRect(width: 1000, height: 1500, framing: .init(scale: 2, offsetY: -1))
        XCTAssertEqual(bottom.y + bottom.height, 1500)

        // Out-of-range values are clamped.
        let wild = AvatarLookResolver.cropRect(width: 1000, height: 1000, framing: .init(scale: 9, offsetY: 5))
        XCTAssertEqual(wild.width, 400)
        XCTAssertEqual(wild.y, 0)
    }
}
