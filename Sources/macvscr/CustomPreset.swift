import Foundation

/// A user-defined preset. Source of truth is logical W/H + hidpi (mirrors
/// `VirtualDisplayConfig`'s logical fields); aspect is derived for display.
/// Identity is a stable `UUID`, so **names may repeat**.
struct CustomPreset: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var logicalWidth: UInt32
    var logicalHeight: UInt32
    var hidpi: Bool

    init(id: UUID = UUID(), name: String, logicalWidth: UInt32,
         logicalHeight: UInt32, hidpi: Bool) {
        self.id = id
        self.name = name
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.hidpi = hidpi
    }

    // MARK: Derived (display only)

    var aspect: Geometry.Aspect {
        Geometry.aspectFrom(width: logicalWidth, height: logicalHeight)
    }

    var physicalWidth: UInt32 { logicalWidth * (hidpi ? 2 : 1) }
    var physicalHeight: UInt32 { logicalHeight * (hidpi ? 2 : 1) }

    /// Pixels-per-inch used for the virtual panel identity (matches
    /// `VirtualDisplayConfig.ppi`: 218 for Retina @2x, 109 otherwise).
    var ppi: Double { hidpi ? 218 : 109 }

    /// Physical screen size in millimetres, derived from physical pixels + ppi.
    var screenMM: (width: Double, height: Double) {
        let pxPerMM = ppi / 25.4
        return (Double(physicalWidth) / pxPerMM, Double(physicalHeight) / pxPerMM)
    }

    /// Diagonal in inches.
    var diagonalInches: Double {
        let (w, h) = screenMM
        return (sqrt(w * w + h * h) / 25.4).rounded(FloatingPointRoundingRule.toNearestOrEven)
    }

    /// "2560×1440 @2x"
    var resolutionLabel: String { "\(logicalWidth)×\(logicalHeight)\(hidpi ? " @2x" : "")" }

    /// Tray row label: trimmed name + resolution. Nameless → plain resolution.
    var menuLabel: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? resolutionLabel : "\(trimmed) · \(resolutionLabel)"
    }
}
