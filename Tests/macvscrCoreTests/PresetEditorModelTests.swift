import XCTest
@testable import macvscrCore

final class PresetEditorModelTests: XCTestCase {

    // MARK: - Fixtures

    /// A 3440×1440 @2x (21:9) preset — the project's default config.
    private func defaultPreset() -> CustomPreset {
        CustomPreset(name: "UW", logicalWidth: 3440, logicalHeight: 1440, hidpi: true)
    }

    // MARK: - Initialization & load

    func testInitFromPreset() {
        let p = defaultPreset()
        let m = PresetEditorModel(p)
        XCTAssertEqual(m.logicalWidth, 3440)
        XCTAssertEqual(m.logicalHeight, 1440)
        XCTAssertTrue(abs(m.aspectFactor - 3440.0 / 1440.0) < 0.01)
        XCTAssertTrue(m.hidpi)
        XCTAssertNil(m.dpiPercent)
        XCTAssertEqual(m.effectiveDpiPercent, 200)
    }

    func testLoadResetsAllFields() {
        let m = PresetEditorModel()
        m.load(defaultPreset())
        XCTAssertEqual(m.name, "UW")
        XCTAssertEqual(m.logicalWidth, 3440)
    }

    // MARK: - setWidth

    func testSetWidthLockAspectOn() {
        let m = PresetEditorModel(defaultPreset())
        m.lockAspect = true
        m.setWidth(2560)
        XCTAssertEqual(m.logicalWidth, 2560)
        XCTAssertEqual(m.logicalHeight, 1072)   // 2560 / (3440/1440) ≈ 1072
    }

    func testSetWidthLockAspectOff() {
        let m = PresetEditorModel(defaultPreset())
        m.lockAspect = false
        let oldHeight = m.logicalHeight
        m.setWidth(2560)
        XCTAssertEqual(m.logicalWidth, 2560)
        XCTAssertEqual(m.logicalHeight, oldHeight)   // height unchanged
    }

    // MARK: - setHeight

    func testSetHeightLockAspectOn() {
        let m = PresetEditorModel(defaultPreset())
        m.lockAspect = true
        let oldWidth = m.logicalWidth
        m.setHeight(1080)
        XCTAssertEqual(m.logicalWidth, oldWidth)   // width unchanged
        XCTAssertEqual(m.logicalHeight, 1080)
    }

    func testSetHeightLockAspectOff() {
        let m = PresetEditorModel(defaultPreset())
        m.lockAspect = false
        m.setHeight(1080)
        // Keep aspect → width = height × factor
        let expectedWidth = UInt32((Double(1080) * m.aspectFactor).rounded())
        XCTAssertEqual(m.logicalWidth, expectedWidth)
    }

    // MARK: - setAspect / setAspectKeepingHeight

    func testSetAspectKeepsWidth() {
        let m = PresetEditorModel(defaultPreset())
        m.setAspect(16.0 / 9.0)
        XCTAssertEqual(m.logicalWidth, 3440)   // unchanged
        XCTAssertEqual(m.logicalHeight, 1935)  // 3440 / (16/9) ≈ 1935
    }

    func testSetAspectKeepingHeight() {
        let m = PresetEditorModel(defaultPreset())
        m.setAspectKeepingHeight(16.0 / 9.0)
        XCTAssertEqual(m.logicalHeight, 1440)   // unchanged
        let expectedWidth = UInt32((Double(1440) * 16.0 / 9.0).rounded())
        XCTAssertEqual(m.logicalWidth, expectedWidth)
    }

    // MARK: - setDpi

    func testSetDpiKeepLogical() {
        let m = PresetEditorModel(defaultPreset())
        m.dpiKeepPhysical = false   // Keep Logical (default)
        let oldLogicalW = m.logicalWidth
        let oldLogicalH = m.logicalHeight
        m.setDpi(250)
        XCTAssertEqual(m.logicalWidth, oldLogicalW)   // logical unchanged
        XCTAssertEqual(m.logicalHeight, oldLogicalH)
        XCTAssertEqual(m.effectiveDpiPercent, 250)
        // physical = logical × 2.5
        XCTAssertEqual(m.physicalWidth, UInt32(Double(oldLogicalW) * 2.5))
    }

    func testSetDpiKeepPhysical() {
        let m = PresetEditorModel(defaultPreset())
        m.dpiKeepPhysical = true    // Keep Physical
        let oldPhysicalW = m.physicalWidth
        let oldPhysicalH = m.physicalHeight
        m.setDpi(250)
        XCTAssertEqual(m.physicalWidth, oldPhysicalW)   // physical unchanged
        XCTAssertEqual(m.physicalHeight, oldPhysicalH)
        // logical = physical / 2.5
        XCTAssertEqual(m.logicalWidth, UInt32(Double(oldPhysicalW) / 2.5))
    }

    func testSetDpi200NormalizesToNil() {
        let m = PresetEditorModel(defaultPreset())
        m.setDpi(250)
        XCTAssertNotNil(m.dpiPercent)
        m.setDpi(200)
        XCTAssertNil(m.dpiPercent)
    }

    func testSetDpiClampsBelow100() {
        let m = PresetEditorModel(defaultPreset())
        m.setDpi(50)
        XCTAssertEqual(m.effectiveDpiPercent, 100)
    }

    func testSetDpiClampsAbove400() {
        let m = PresetEditorModel(defaultPreset())
        m.setDpi(999)
        XCTAssertEqual(m.effectiveDpiPercent, 400)
    }

    // MARK: - differs

    func testDiffersAfterEdit() {
        let p = defaultPreset()
        let m = PresetEditorModel(p)
        XCTAssertFalse(m.differs(from: p))
        m.setWidth(2560)
        XCTAssertTrue(m.differs(from: p))
    }

    func testDiffersFalseAfterLoad() {
        let p = defaultPreset()
        let m = PresetEditorModel()
        m.setWidth(9999)
        m.load(p)
        XCTAssertFalse(m.differs(from: p))
    }

    // MARK: - snapshot round-trip

    func testSnapshotRoundTrip() {
        let p = defaultPreset()
        let m = PresetEditorModel(p)
        m.setWidth(2560)
        m.setDpi(150)
        let snap = m.snapshot()
        let m2 = PresetEditorModel(snap)
        XCTAssertEqual(m2.logicalWidth, 2560)
        XCTAssertEqual(m2.dpiPercent, 150)
        XCTAssertEqual(m2.aspectFactor, m.aspectFactor, accuracy: 0.001)
    }

    // MARK: - Derived property consistency

    func testPhysicalEqualsLogicalTimesScale() {
        let m = PresetEditorModel(defaultPreset())
        m.setDpi(175)
        let scale = 1.75
        XCTAssertEqual(m.physicalWidth, UInt32((Double(m.logicalWidth) * scale).rounded()))
        XCTAssertEqual(m.physicalHeight, UInt32((Double(m.logicalHeight) * scale).rounded()))
    }

    func testPPIIs109TimesScale() {
        let m = PresetEditorModel(defaultPreset())
        m.setDpi(175)
        XCTAssertEqual(m.ppi, 109 * 1.75, accuracy: 0.01)
    }

    func testScreenMMConsistency() {
        let m = PresetEditorModel(defaultPreset())
        m.setDpi(150)
        let pxPerMM = m.ppi / 25.4
        let (w, h) = m.screenMM
        XCTAssertEqual(w, Double(m.physicalWidth) / pxPerMM, accuracy: 0.01)
        XCTAssertEqual(h, Double(m.physicalHeight) / pxPerMM, accuracy: 0.01)
    }

    func testNonHidpiScaleIs1() {
        let m = PresetEditorModel(CustomPreset(name: "SD", logicalWidth: 1920, logicalHeight: 1080, hidpi: false))
        XCTAssertEqual(m.scale, 1.0)
        XCTAssertEqual(m.ppi, 109.0)
        XCTAssertEqual(m.physicalWidth, 1920)
    }

    // MARK: - densitySuffix

    func testDensitySuffix() {
        XCTAssertEqual(Geometry.densitySuffix(scale: 2), "@2x")
        XCTAssertEqual(Geometry.densitySuffix(scale: 1.5), "@1.5x")
        XCTAssertEqual(Geometry.densitySuffix(scale: 3), "@3x")
        XCTAssertEqual(Geometry.densitySuffix(scale: 1), "@1x")
    }

    func testDensitySuffixFromDpiPercent() {
        XCTAssertEqual(Geometry.densitySuffix(dpiPercent: nil), "@2x")
        XCTAssertEqual(Geometry.densitySuffix(dpiPercent: 200), "@2x")
        XCTAssertEqual(Geometry.densitySuffix(dpiPercent: 150), "@1.5x")
        XCTAssertEqual(Geometry.densitySuffix(dpiPercent: 300), "@3x")
    }

    // MARK: - Default UI preferences

    func testDefaultLockAspect() {
        let m = PresetEditorModel()
        XCTAssertTrue(m.lockAspect)
    }

    func testDefaultKeepLogical() {
        let m = PresetEditorModel()
        XCTAssertFalse(m.dpiKeepPhysical)   // false = Keep Logical
    }
}
