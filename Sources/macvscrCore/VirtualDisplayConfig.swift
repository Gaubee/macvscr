import Foundation

/// Full description of a virtual display, expressed in LOGICAL pixels.
/// Physical = logical × scale (2.0 = Retina @2x). The display name is suffixed
/// with the physical size so each geometry gets a distinct EDID identity.
public struct VirtualDisplayConfig: Equatable, Codable {
    public var logicalWidth: UInt32
    public var logicalHeight: UInt32
    public var hidpi: Bool
    public var refreshRate: Double
    public var name: String

    /// DPI scaling percent, only meaningful when `hidpi` is on. `nil` = 200%
    /// (the default, = 2.0× backing). `physical = logical × scale`.
    /// Optional so existing config.json without this key decode unchanged.
    public var dpiPercent: Int?

    /// Backing scale factor (physical / logical). 2.0 = classic Retina @2x.
    public var scale: Double { hidpi ? Double(effectiveDpiPercent) / 100 : 1 }

    public var physicalWidth: UInt32 {
        UInt32((Double(logicalWidth) * scale).rounded())
    }
    public var physicalHeight: UInt32 {
        UInt32((Double(logicalHeight) * scale).rounded())
    }

    /// Pixels-per-inch driving `sizeInMillimeters`. Linear in scale:
    /// 2.0 → 218 (iMac Retina), 1.0 → 109. Matches `CustomPreset.ppi`.
    public var ppi: Double { hidpi ? 109 * scale : 109 }

    /// Effective percent, treating `nil` as the 200% default.
    public var effectiveDpiPercent: Int { dpiPercent ?? 200 }

    public init(logicalWidth: UInt32, logicalHeight: UInt32, hidpi: Bool,
                refreshRate: Double = 60, dpiPercent: Int? = nil, name: String) {
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.hidpi = hidpi
        self.refreshRate = refreshRate
        self.dpiPercent = dpiPercent
        self.name = name
    }
}
