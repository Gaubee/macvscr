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
}
