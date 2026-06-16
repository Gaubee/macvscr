import Foundation
import Combine

/// 编辑 `CustomPreset` 的唯一事实来源。它拥有 **源数据**
/// `(name, logicalWidth, aspectFactor, hidpi, dpiPercent)` 以及两个 UI 切换
/// 首选项（`lockAspect`, `dpiKeepPhysical`）。其他所有内容——`logicalHeight`、
/// 物理像素、`ppi`、屏幕尺寸——均为 **计算属性**，因此编辑任何一个源字段
/// 都会自动保持其他字段的同步。不需要手工编写交叉重新计算逻辑。
///
/// 编辑方法（`setWidth`, `setHeight`, `setAspect`, `setAspectKeepingHeight`,
/// `setDpi`）封装了所有联动语义，使 UI 绑定变得轻量且可测试。
public final class PresetEditorModel: ObservableObject {

    // MARK: Source data (what gets persisted)

    @Published public var id: UUID
    @Published public var name: String
    @Published public var logicalWidth: UInt32
    @Published public var aspectFactor: Double
    @Published public var hidpi: Bool
    @Published public var dpiPercent: Int?          // nil = 200% default

    // MARK: UI toggle preferences (not persisted)

    @Published public var lockAspect: Bool = true
    @Published public var dpiKeepPhysical: Bool = false   // false = Keep Logical (default)

    // MARK: Init / load

    public init() {
        self.id = UUID()
        self.name = ""
        self.logicalWidth = 3440
        self.aspectFactor = 21.0 / 9.0
        self.hidpi = true
        self.dpiPercent = nil
    }

    public init(_ preset: CustomPreset) {
        self.id = preset.id
        self.name = preset.name
        self.logicalWidth = preset.logicalWidth
        self.aspectFactor = preset.aspectFactor
        self.hidpi = preset.hidpi
        self.dpiPercent = preset.dpiPercent
    }

    /// Re-seed from a preset (selection change / external update / save).
    public func load(_ preset: CustomPreset) {
        id = preset.id
        name = preset.name
        logicalWidth = preset.logicalWidth
        aspectFactor = preset.aspectFactor
        hidpi = preset.hidpi
        dpiPercent = preset.dpiPercent
    }

    /// Snapshot back to a `CustomPreset` for persistence / apply.
    public func snapshot() -> CustomPreset {
        CustomPreset(
            id: id,
            name: name,
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,   // derived; included for the memberwise init
            hidpi: hidpi,
            dpiPercent: dpiPercent
        )
    }

    // MARK: Derived properties (read-only — never set these directly)

    public var aspect: Geometry.Aspect { Geometry.aspectFrom(factor: aspectFactor) }

    public var logicalHeight: UInt32 { Geometry.height(forWidth: logicalWidth, aspect: aspect) }

    public var effectiveDpiPercent: Int { dpiPercent ?? 200 }

    public var scale: Double { hidpi ? Double(effectiveDpiPercent) / 100 : 1 }

    public var physicalWidth: UInt32 { UInt32((Double(logicalWidth) * scale).rounded()) }
    public var physicalHeight: UInt32 { UInt32((Double(logicalHeight) * scale).rounded()) }

    public var ppi: Double { hidpi ? 109 * scale : 109 }

    public var screenMM: (width: Double, height: Double) {
        let pxPerMM = ppi / 25.4
        return (Double(physicalWidth) / pxPerMM, Double(physicalHeight) / pxPerMM)
    }

    public var diagonalInches: Double {
        let (w, h) = screenMM
        return (sqrt(w * w + h * h) / 25.4).rounded(FloatingPointRoundingRule.toNearestOrEven)
    }

    public var densitySuffix: String { Geometry.densitySuffix(scale: scale) }

    public var resolutionLabel: String {
        "\(logicalWidth)×\(logicalHeight)\(hidpi ? " " + densitySuffix : "")"
    }

    // MARK: Edit methods (all coupling logic lives here — single source of truth)

    /// Edit the logical width. When aspect is locked, height follows from the
    /// unchanged aspect factor. When unlocked, the aspect factor re-derives
    /// from the new width and the held height.
    public func setWidth(_ w: UInt32) {
        if lockAspect {
            logicalWidth = w
            // aspectFactor unchanged → logicalHeight auto-derives
        } else {
            let heldHeight = Double(logicalHeight)
            aspectFactor = heldHeight > 0 ? Double(w) / heldHeight : aspectFactor
            logicalWidth = w
        }
    }

    /// Edit the logical height. Since height is derived, this writes back into
    /// the appropriate source field depending on the lock mode:
    ///   - locked  → keep width, re-derive aspect from new W/H
    ///   - unlocked → keep aspect, re-derive width from typed height
    public func setHeight(_ h: UInt32) {
        if lockAspect {
            aspectFactor = h > 0 ? Double(logicalWidth) / Double(h) : aspectFactor
        } else {
            logicalWidth = UInt32((Double(h) * aspectFactor).rounded())
        }
    }

    /// Set the aspect ratio (keeps width; height follows).
    public func setAspect(_ factor: Double) {
        aspectFactor = factor
    }

    /// Set the aspect ratio while keeping the current height (re-derives width).
    public func setAspectKeepingHeight(_ factor: Double) {
        let heldHeight = Double(logicalHeight)
        logicalWidth = max(1, UInt32((heldHeight * factor).rounded()))
        aspectFactor = factor
    }

    /// Set the DPI scaling percentage. Under Keep Physical, the physical pixel
    /// count is held and logical re-derives; under Keep Logical (default),
    /// only the scale changes.
    public func setDpi(_ pct: Int) {
        let clamped = max(100, min(400, pct))
        if dpiKeepPhysical {
            // Capture physical BEFORE changing dpiPercent (physical depends on it).
            let heldPhysical = physicalWidth
            dpiPercent = (clamped == 200) ? nil : clamped
            let newScale = Double(clamped) / 100
            logicalWidth = Geometry.logicalFrom(physical: heldPhysical, scale: newScale)
        } else {
            dpiPercent = (clamped == 200) ? nil : clamped
        }
    }

    // MARK: Comparison

    /// Does the editor differ from a given persisted preset? (drives the
    /// Save button's enabled state via pure data comparison.)
    public func differs(from preset: CustomPreset) -> Bool {
        snapshot() != preset
    }
}
