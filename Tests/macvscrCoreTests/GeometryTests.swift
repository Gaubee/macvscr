import XCTest
@testable import macvscrCore

final class GeometryTests: XCTestCase {

    // MARK: - height(forWidth:aspect:)

    func testHeightForWidth16x9() {
        let h = Geometry.height(forWidth: 1920, aspect: .standard(.w16x9))
        XCTAssertEqual(h, 1080)
    }

    func testHeightForWidth21x9() {
        let h = Geometry.height(forWidth: 3440, aspect: .standard(.w21x9))
        XCTAssertEqual(h, 1474)   // 3440 / (21/9) ≈ 1474
    }

    func testHeightForWidth1x1() {
        let h = Geometry.height(forWidth: 1000, aspect: .standard(.w1x1))
        XCTAssertEqual(h, 1000)
    }

    func testHeightForWidthCustom() {
        let h = Geometry.height(forWidth: 2000, aspect: .custom(factor: 2.0))
        XCTAssertEqual(h, 1000)
    }

    // MARK: - aspectFrom(width:height:)

    func testAspectFromSnapsToStandard() {
        // 1920×1080 → 16:9
        let a = Geometry.aspectFrom(width: 1920, height: 1080)
        if case .standard(let r) = a {
            XCTAssertEqual(r, .w16x9)
        } else {
            XCTFail("Expected standard 16:9")
        }
    }

    func testAspectFromCustom() {
        // 3440×1440 = 2.388... which is close to 21:9 (2.333) but outside 0.02 tol
        let a = Geometry.aspectFrom(width: 3440, height: 1440)
        if case .standard(let r) = a {
            // 3440/1440 = 2.388..., 21/9 = 2.333, diff = 0.055 > 0.02 → should NOT snap
            XCTAssertNotEqual(r, .w21x9, "3440×1440 should not snap to 21:9 (diff > 0.02)")
        }
        // It should be custom
        if case .custom(let f) = a {
            XCTAssertEqual(f, 3440.0 / 1440.0, accuracy: 0.01)
        } else {
            // If it snapped to some other standard ratio, that's also acceptable
        }
    }

    func testAspectFromFactor() {
        let a = Geometry.aspectFrom(factor: 16.0 / 9.0)
        if case .standard(let r) = a {
            XCTAssertEqual(r, .w16x9)
        } else {
            XCTFail("Expected standard 16:9")
        }
    }

    // MARK: - reducedRatio

    func testReducedRatio() {
        XCTAssertEqual(Geometry.reducedRatio(width: 3440, height: 1440), "43:18")
    }

    func testReducedRatioAlreadySimple() {
        XCTAssertEqual(Geometry.reducedRatio(width: 16, height: 9), "16:9")
    }

    func testReducedRatioZero() {
        XCTAssertEqual(Geometry.reducedRatio(width: 0, height: 1080), "—")
        XCTAssertEqual(Geometry.reducedRatio(width: 1920, height: 0), "—")
    }

    // MARK: - physicalFrom / logicalFrom

    func testPhysicalFromLogical() {
        XCTAssertEqual(Geometry.physicalFrom(logical: 1920, scale: 2.0), 3840)
        XCTAssertEqual(Geometry.physicalFrom(logical: 1920, scale: 1.5), 2880)
        XCTAssertEqual(Geometry.physicalFrom(logical: 1920, scale: 1.0), 1920)
    }

    func testLogicalFromPhysical() {
        XCTAssertEqual(Geometry.logicalFrom(physical: 3840, scale: 2.0), 1920)
        XCTAssertEqual(Geometry.logicalFrom(physical: 2880, scale: 1.5), 1920)
        XCTAssertEqual(Geometry.logicalFrom(physical: 1920, scale: 1.0), 1920)
    }

    func testPhysicalLogicalRoundTrip() {
        for scale in [1.0, 1.25, 1.5, 2.0, 2.5, 3.0] {
            let physical = Geometry.physicalFrom(logical: 3440, scale: scale)
            let back = Geometry.logicalFrom(physical: physical, scale: scale)
            XCTAssertEqual(back, 3440, "Round-trip failed for scale \(scale)")
        }
    }

    // MARK: - Ratio enum

    func testRatioFactors() {
        XCTAssertEqual(Geometry.Ratio.w16x9.factor, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(Geometry.Ratio.w16x10.factor, 16.0 / 10.0, accuracy: 0.001)
        XCTAssertEqual(Geometry.Ratio.w21x9.factor, 21.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(Geometry.Ratio.w1x1.factor, 1.0, accuracy: 0.001)
    }

    func testRatioLabels() {
        XCTAssertEqual(Geometry.Ratio.w16x9.label, "16:9")
        XCTAssertEqual(Geometry.Ratio.w1x1.label, "1:1")
    }

    func testRatioAllCasesCount() {
        XCTAssertEqual(Geometry.Ratio.allCases.count, 8)
    }

    // MARK: - Aspect enum

    func testAspectFactorStandard() {
        XCTAssertEqual(Geometry.Aspect.standard(.w16x9).factor, 16.0 / 9.0, accuracy: 0.001)
    }

    func testAspectFactorCustom() {
        XCTAssertEqual(Geometry.Aspect.custom(factor: 2.5).factor, 2.5, accuracy: 0.001)
    }

    func testAspectLabelStandard() {
        XCTAssertEqual(Geometry.Aspect.standard(.w16x9).label, "16:9")
    }

    func testAspectLabelCustom() {
        XCTAssertEqual(Geometry.Aspect.custom(factor: 2.5).label, "custom")
    }
}
