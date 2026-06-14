import Foundation

/// A recommended geometry. Defined in PHYSICAL (native panel) pixels + hidpi;
/// displayed in LOGICAL pixels (`@2x` when HiDPI). iMac entries carry a tail.
public struct Preset: Equatable {
    public let key: String
    public let physicalWidth: UInt32
    public let physicalHeight: UInt32
    public let hidpi: Bool
    public let tail: String

    public var logicalWidth: UInt32 { physicalWidth / (hidpi ? 2 : 1) }
    public var logicalHeight: UInt32 { physicalHeight / (hidpi ? 2 : 1) }

    public var menuLabel: String {
        let res = "\(logicalWidth)×\(logicalHeight)\(hidpi ? " @2x" : "")"
        return tail.isEmpty ? res : "\(res) \(tail)"
    }
}

public enum Presets {
    /// One merged list (iMac presets folded in, distinguished by tail).
    public static let all: [Preset] = [
        Preset(key: "1080p",   physicalWidth: 1920, physicalHeight: 1080, hidpi: false, tail: "· 1080p"),
        Preset(key: "4k",      physicalWidth: 3840, physicalHeight: 2160, hidpi: true,  tail: "· 4K"),
        Preset(key: "1440p",   physicalWidth: 2560, physicalHeight: 1440, hidpi: false, tail: "· 1440p"),
        Preset(key: "imac215", physicalWidth: 4096, physicalHeight: 2304, hidpi: true,  tail: "· iMac 21.5\""),
        Preset(key: "imac24",  physicalWidth: 4480, physicalHeight: 2520, hidpi: true,  tail: "· iMac 24\""),
        Preset(key: "imac27",  physicalWidth: 5120, physicalHeight: 2880, hidpi: true,  tail: "· iMac 27\" 5K"),
        Preset(key: "uw3440",  physicalWidth: 3440, physicalHeight: 1440, hidpi: false, tail: "· UW"),
        Preset(key: "uw3840",  physicalWidth: 3840, physicalHeight: 1600, hidpi: false, tail: "· UW"),
    ]

    /// Logical pixel widths offered in the "宽度" submenu.
    public static let widths: [UInt32] = [1920, 2560, 2880, 3008, 3440, 3840, 4480, 5120]
    /// Logical pixel heights offered in the "高度" submenu.
    public static let heights: [UInt32] = [1080, 1200, 1440, 1600, 2160]

    public static func find(key: String) -> Preset? { all.first { $0.key == key } }
}
