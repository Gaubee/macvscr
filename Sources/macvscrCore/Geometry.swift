import Foundation

/// Aspect-ratio math. All user-facing dimensions are LOGICAL pixels; the aspect
/// links width and height (height = width / aspect.factor). An aspect may be a
/// known ratio or an arbitrary custom factor (from a typed height or "W:H").
public enum Geometry {
    public enum Ratio: String, CaseIterable {
        case w16x9 = "16:9"
        case w16x10 = "16:10"
        case w21x9 = "21:9"
        case w32x9 = "32:9"
        case w4x3 = "4:3"
        case w3x2 = "3:2"
        case w5x4 = "5:4"
        case w1x1 = "1:1"

        /// width / height
        public var factor: Double {
            switch self {
            case .w16x9:  return 16.0 / 9.0
            case .w16x10: return 16.0 / 10.0
            case .w21x9:  return 21.0 / 9.0
            case .w32x9:  return 32.0 / 9.0
            case .w4x3:   return 4.0 / 3.0
            case .w3x2:   return 3.0 / 2.0
            case .w5x4:   return 5.0 / 4.0
            case .w1x1:   return 1.0
            }
        }

        public var label: String { rawValue }
    }

    /// Aspect that is either a known ratio or an arbitrary custom factor.
    public enum Aspect: Equatable {
        case standard(Ratio)
        case custom(factor: Double)

        public var factor: Double {
            switch self {
            case .standard(let r): return r.factor
            case .custom(let f):   return f
            }
        }

        public var label: String {
            switch self {
            case .standard(let r): return r.label
            case .custom:          return "custom"
            }
        }
    }

    /// Height for a given (logical) width + aspect.
    public static func height(forWidth width: UInt32, aspect: Aspect) -> UInt32 {
        guard aspect.factor > 0 else { return width }
        return UInt32((Double(width) / aspect.factor).rounded())
    }

    /// Build an aspect from a width×height pair (snaps to a standard ratio if close).
    public static func aspectFrom(width: UInt32, height: UInt32) -> Aspect {
        guard height > 0 else { return .standard(.w16x9) }
        return aspectFrom(factor: Double(width) / Double(height))
    }

    /// Build an aspect from a raw factor (snaps to a standard ratio if within tolerance).
    public static func aspectFrom(factor: Double) -> Aspect {
        if let r = Ratio.allCases.first(where: { abs($0.factor - factor) < 0.02 }) {
            return .standard(r)
        }
        return .custom(factor: factor)
    }

    /// A width×height pair reduced to its smallest integer W:H ratio (e.g.
    /// 3440×1440 → "43:18"). Shared by the tray's Aspect "Custom…" item and by
    /// the preset-manager detail preview.
    public static func reducedRatio(width: UInt32, height: UInt32) -> String {
        func gcd(_ a: UInt32, _ b: UInt32) -> UInt32 { b == 0 ? a : gcd(b, a % b) }
        guard height > 0, width > 0 else { return "—" }
        let d = gcd(width, height)
        return "\(width / d):\(height / d)"
    }

    // MARK: Density (physical / logical) scale helpers

    /// Physical pixels for a logical dimension at a given backing scale.
    public static func physicalFrom(logical: UInt32, scale: Double) -> UInt32 {
        guard scale > 0 else { return logical }
        return UInt32((Double(logical) * scale).rounded())
    }

    /// Logical pixels for a physical dimension at a given backing scale.
    public static func logicalFrom(physical: UInt32, scale: Double) -> UInt32 {
        guard scale > 0 else { return physical }
        return UInt32((Double(physical) / scale).rounded())
    }

    /// Density suffix string, e.g. "@2x" (scale 2), "@1.5x" (scale 1.5).
    /// Integer scales render without a decimal; others keep one decimal place.
    public static func densitySuffix(scale: Double) -> String {
        if scale == scale.rounded() {
            return "@\(Int(scale))x"
        }
        return String(format: "@%.1fx", scale)
    }

    /// Density suffix from a DPI percent (nil = 200% = "@2x").
    public static func densitySuffix(dpiPercent: Int?) -> String {
        densitySuffix(scale: Double(dpiPercent ?? 200) / 100)
    }
}
