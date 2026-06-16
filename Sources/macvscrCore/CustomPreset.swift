import Foundation

/// A user-defined preset. **Derived model**: the source of truth is
/// `(logicalWidth, aspectFactor, hidpi, dpiPercent)` — mirroring TrayController.
/// `logicalHeight`, physical pixels, ppi, screen size are ALL derived, so any
/// edit to one source field automatically keeps everything else in sync (no
/// hand-written cross-recomputation). Identity is a stable `UUID`, so **names
/// may repeat**.
public struct CustomPreset: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var logicalWidth: UInt32
    /// Aspect as a factor (W/H). Stored as a Double for Codable; snap-rebuilt
    /// to a standard `Geometry.Aspect` via `Geometry.aspectFrom(factor:)`.
    public var aspectFactor: Double
    public var hidpi: Bool
    /// DPI scaling percent (only meaningful when `hidpi`); `nil` = 200%.
    public var dpiPercent: Int?

    public init(id: UUID = UUID(), name: String, logicalWidth: UInt32,
         logicalHeight: UInt32, hidpi: Bool, dpiPercent: Int? = nil) {
        self.id = id
        self.name = name
        self.logicalWidth = logicalWidth
        self.aspectFactor = logicalHeight > 0
            ? Double(logicalWidth) / Double(logicalHeight)
            : 16.0 / 9.0
        self.hidpi = hidpi
        self.dpiPercent = dpiPercent
    }

    // MARK: Derived (display only)

    public var aspect: Geometry.Aspect { Geometry.aspectFrom(factor: aspectFactor) }
    public var logicalHeight: UInt32 { Geometry.height(forWidth: logicalWidth, aspect: aspect) }

    public var scale: Double { hidpi ? Double(effectiveDpiPercent) / 100 : 1 }
    public var physicalWidth: UInt32 {
        UInt32((Double(logicalWidth) * scale).rounded())
    }
    public var physicalHeight: UInt32 {
        UInt32((Double(logicalHeight) * scale).rounded())
    }

    /// Effective DPI percent, treating `nil` as the 200% default.
    public var effectiveDpiPercent: Int { dpiPercent ?? 200 }

    /// Pixels-per-inch driving screen size. Linear in scale:
    /// 2.0 → 218 (iMac Retina), 1.0 → 109. Matches `VirtualDisplayConfig.ppi`.
    public var ppi: Double { hidpi ? 109 * scale : 109 }

    /// Physical screen size in millimetres, derived from physical pixels ÷ ppi.
    public var screenMM: (width: Double, height: Double) {
        let pxPerMM = ppi / 25.4
        return (Double(physicalWidth) / pxPerMM, Double(physicalHeight) / pxPerMM)
    }

    /// Diagonal in inches.
    public var diagonalInches: Double {
        let (w, h) = screenMM
        return (sqrt(w * w + h * h) / 25.4).rounded(FloatingPointRoundingRule.toNearestOrEven)
    }

    /// "2560×1440 @2x"
    public var resolutionLabel: String {
        "\(logicalWidth)×\(logicalHeight)\(hidpi ? " " + Geometry.densitySuffix(scale: scale) : "")"
    }

    /// Tray row label: trimmed name + resolution. Nameless → plain resolution.
    public var menuLabel: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? resolutionLabel : "\(trimmed) · \(resolutionLabel)"
    }
}
