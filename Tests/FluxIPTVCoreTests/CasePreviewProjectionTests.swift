import XCTest
@testable import FluxIPTVCore

final class CasePreviewProjectionTests: XCTestCase {
    private let viewport = CGSize(width: 1_000, height: 800)

    private func rectangle(_ rect: CGRect, viewport: CGSize? = nil) -> CasePreviewProjection? {
        CasePreviewProjection(topLeft: CGPoint(x: rect.minX, y: rect.minY),
                              topRight: CGPoint(x: rect.maxX, y: rect.minY),
                              bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
                              bottomLeft: CGPoint(x: rect.minX, y: rect.maxY),
                              viewport: viewport ?? self.viewport)
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-7, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-7, file: file, line: line)
    }

    private func assertCorners(_ projection: CasePreviewProjection, _ corners: [CGPoint], file: StaticString = #filePath, line: UInt = #line) {
        let size = projection.surfaceSize
        for (local, expected) in zip([CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)], corners) {
            assertPoint(projection.project(local), expected, file: file, line: line)
        }
    }

    func testIdentityAndTranslationMatchCATransform3DConventions() throws {
        let identity = try XCTUnwrap(rectangle(CGRect(x: 0, y: 0, width: 480, height: 270)))
        XCTAssertEqual(identity.surfaceSize, CGSize(width: 480, height: 270))
        XCTAssertEqual(identity.matrix.m11, 1)
        XCTAssertEqual(identity.matrix.m22, 1)
        XCTAssertEqual(identity.matrix.m12, 0)
        XCTAssertEqual(identity.matrix.m21, 0)
        XCTAssertEqual(identity.matrix.m14, 0)
        XCTAssertEqual(identity.matrix.m24, 0)
        assertPoint(identity.project(CGPoint(x: 120, y: 90)), CGPoint(x: 120, y: 90))

        let translated = try XCTUnwrap(rectangle(CGRect(x: 35, y: 64, width: 480, height: 270)))
        XCTAssertEqual(translated.bounds, CGRect(x: 35, y: 64, width: 480, height: 270))
        XCTAssertEqual(translated.matrix.m41, 35)
        XCTAssertEqual(translated.matrix.m42, 64)
        assertPoint(translated.project(CGPoint(x: 120, y: 90)), CGPoint(x: 155, y: 154))
        assertCorners(translated, [CGPoint(x: 35, y: 64), CGPoint(x: 515, y: 64), CGPoint(x: 515, y: 334), CGPoint(x: 35, y: 334)])
    }

    func testAffineSkewPreservesAllCornersAndTheCenter() throws {
        let corners = [CGPoint(x: 100, y: 60), CGPoint(x: 500, y: 140), CGPoint(x: 430, y: 420), CGPoint(x: 30, y: 340)]
        let projection = try XCTUnwrap(CasePreviewProjection(topLeft: corners[0], topRight: corners[1], bottomRight: corners[2], bottomLeft: corners[3], viewport: viewport))
        assertCorners(projection, corners)
        XCTAssertEqual(projection.matrix.m14, 0)
        XCTAssertEqual(projection.matrix.m24, 0)
        assertPoint(projection.project(CGPoint(x: projection.surfaceSize.width / 2, y: projection.surfaceSize.height / 2)), CGPoint(x: 265, y: 240))
        XCTAssertTrue(projection.isAutoplayEligible)
    }

    func testPerspectiveMapsCornersAndAnIndependentlyKnownInteriorPoint() throws {
        // These corners come from x=(400u+50)/(1+u/2+v/4),
        // y=(300v+40)/(1+u/2+v/4). The midpoint is not the average of corners.
        let corners = [CGPoint(x: 50, y: 40), CGPoint(x: 300, y: 40.0 / 1.5),
                       CGPoint(x: 450.0 / 1.75, y: 340.0 / 1.75), CGPoint(x: 40, y: 272)]
        let projection = try XCTUnwrap(CasePreviewProjection(topLeft: corners[0], topRight: corners[1], bottomRight: corners[2], bottomLeft: corners[3], viewport: viewport))
        assertCorners(projection, corners)
        XCTAssertNotEqual(projection.matrix.m14, 0)
        XCTAssertNotEqual(projection.matrix.m24, 0)
        assertPoint(projection.project(CGPoint(x: projection.surfaceSize.width / 2, y: projection.surfaceSize.height / 2)),
                    CGPoint(x: 250.0 / 1.375, y: 190.0 / 1.375))
    }

    func testMalformedMirroredFoldedConcaveAndEdgeOnQuadsAreRejected() {
        let invalid: [[CGPoint]] = [
            [.zero, .zero, CGPoint(x: 400, y: 300), CGPoint(x: 0, y: 300)],
            [.zero, CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 300, y: 0)],
            [CGPoint(x: 400, y: 0), .zero, CGPoint(x: 0, y: 300), CGPoint(x: 400, y: 300)],
            [.zero, CGPoint(x: 400, y: 300), CGPoint(x: 400, y: 0), CGPoint(x: 0, y: 300)],
            [.zero, CGPoint(x: 400, y: 0), CGPoint(x: 100, y: 80), CGPoint(x: 0, y: 300)],
            [.zero, CGPoint(x: 480, y: 0), CGPoint(x: 480, y: 1e-9), CGPoint(x: 0, y: 1e-9)],
            [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 400, y: 0), CGPoint(x: 400, y: 300), CGPoint(x: 0, y: 300)],
            [.zero, CGPoint(x: CGFloat.infinity, y: 0), CGPoint(x: 400, y: 300), CGPoint(x: 0, y: 300)]
        ]
        for corners in invalid {
            XCTAssertNil(CasePreviewProjection(topLeft: corners[0], topRight: corners[1], bottomRight: corners[2], bottomLeft: corners[3], viewport: viewport), "\(corners)")
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 300), CGSize(width: 400, height: 0), CGSize(width: CGFloat.infinity, height: 300), CGSize(width: 400, height: CGFloat.nan)] {
            XCTAssertNil(rectangle(CGRect(x: 0, y: 0, width: 400, height: 300), viewport: size))
        }
    }

    func testAutoplayUsesPhysicalOppositeEdgesAndIncludesExactlyTwoHundredPoints() throws {
        XCTAssertTrue(try XCTUnwrap(rectangle(CGRect(x: 0, y: 0, width: 200, height: 200))).isAutoplayEligible)
        XCTAssertFalse(try XCTUnwrap(rectangle(CGRect(x: 0, y: 0, width: 199.99, height: 300))).isAutoplayEligible)
        XCTAssertFalse(try XCTUnwrap(rectangle(CGRect(x: 0, y: 0, width: 300, height: 199.99))).isAutoplayEligible)
        let narrowBottom = try XCTUnwrap(CasePreviewProjection(topLeft: .zero, topRight: CGPoint(x: 300, y: 0), bottomRight: CGPoint(x: 200, y: 400), bottomLeft: CGPoint(x: 100, y: 400), viewport: viewport))
        XCTAssertEqual(narrowBottom.surfaceSize, CGSize(width: 300, height: 400))
        XCTAssertFalse(narrowBottom.isAutoplayEligible)
        let shortRight = try XCTUnwrap(CasePreviewProjection(topLeft: .zero, topRight: CGPoint(x: 400, y: 100), bottomRight: CGPoint(x: 400, y: 250), bottomLeft: CGPoint(x: 0, y: 400), viewport: viewport))
        XCTAssertFalse(shortRight.isAutoplayEligible)
    }

    func testAutoplayRequiresStrictlyMoreThanHalfVisibleAtEveryViewportEdge() throws {
        let viewport = CGSize(width: 500, height: 400)
        let cases: [(CGRect, Bool)] = [
            (CGRect(x: 0, y: 0, width: 400, height: 300), true),
            (CGRect(x: -200, y: 0, width: 400, height: 300), false),
            (CGRect(x: -199.5, y: 0, width: 400, height: 300), true),
            (CGRect(x: -201, y: 0, width: 400, height: 300), false),
            (CGRect(x: 300, y: 0, width: 400, height: 300), false),
            (CGRect(x: 299, y: 0, width: 400, height: 300), true),
            (CGRect(x: 0, y: -150, width: 400, height: 300), false),
            (CGRect(x: 0, y: -149.5, width: 400, height: 300), true),
            (CGRect(x: 0, y: 250, width: 400, height: 300), false),
            (CGRect(x: 0, y: 249, width: 400, height: 300), true),
            (CGRect(x: -100, y: -100, width: 400, height: 300), false),
            (CGRect(x: -99, y: -100, width: 400, height: 300), true),
            (CGRect(x: 500, y: 500, width: 400, height: 300), false)
        ]
        for (rect, expected) in cases {
            XCTAssertEqual(try XCTUnwrap(rectangle(rect, viewport: viewport)).isAutoplayEligible, expected, "\(rect)")
        }
    }

    func testClippingMeasuresTheQuadInsteadOfItsBoundingRectangle() throws {
        func trapezoid(_ height: CGFloat) -> CasePreviewProjection? {
            CasePreviewProjection(topLeft: CGPoint(x: -100, y: 0), topRight: CGPoint(x: 600, y: 0),
                                  bottomRight: CGPoint(x: 400, y: 400), bottomLeft: CGPoint(x: 100, y: 400),
                                  viewport: CGSize(width: 500, height: height))
        }
        // Actual quad area=200,000; visible area=109,800. Its visible bounding
        // rectangle is only 110,000 / 280,000, which would wrongly deny autoplay.
        XCTAssertTrue(try XCTUnwrap(trapezoid(220)).isAutoplayEligible)
        // At 180 points high, only 90,000 of the quad's area remains visible.
        XCTAssertFalse(try XCTUnwrap(trapezoid(180)).isAutoplayEligible)
    }
}
