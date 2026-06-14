import Foundation
import CoreGraphics
import VSCBridge

/// Full description of a virtual display, expressed in LOGICAL pixels.
/// Physical = logical × 2 when HiDPI (Retina). The display name is suffixed
/// with the physical size so each geometry gets a distinct EDID identity.
public struct VirtualDisplayConfig: Equatable, Codable {
    public var logicalWidth: UInt32
    public var logicalHeight: UInt32
    public var hidpi: Bool
    public var refreshRate: Double
    public var name: String
    internal var ppi: Int

    public var physicalWidth: UInt32 { logicalWidth * (hidpi ? 2 : 1) }
    public var physicalHeight: UInt32 { logicalHeight * (hidpi ? 2 : 1) }

    public init(logicalWidth: UInt32, logicalHeight: UInt32, hidpi: Bool,
                refreshRate: Double = 60, name: String) {
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.hidpi = hidpi
        self.refreshRate = refreshRate
        self.name = name
        // Internal-only PPI for sizeInMillimeters metadata (not user-facing).
        self.ppi = hidpi ? 218 : 109
    }
}

/// Owns a single virtual display. Geometry changes are destroy + recreate
/// (the private SPI's applySettings alone does not reliably change maxPixels*).
public final class VirtualDisplay {
    private var ref: VSCDisplayRef?
    public private(set) var displayID: CGDirectDisplayID = 0
    public private(set) var config: VirtualDisplayConfig?

    @discardableResult
    public func create(_ cfg: VirtualDisplayConfig) -> Bool {
        destroy()

        let pw = cfg.physicalWidth
        let ph = cfg.physicalHeight
        // Geometry-encoded name => a distinct EDID-ish identity per physical size,
        // so macOS does not confuse window layouts across different geometries.
        let effectiveName = "\(cfg.name) \(pw)x\(ph)"

        let created: (VSCDisplayRef, UInt32)? = effectiveName.withCString { namePtr in
            var c = VSCDisplayConfig(
                width: pw,
                height: ph,
                refreshRate: cfg.refreshRate,
                hiDPI: cfg.hidpi,
                ppi: Double(cfg.ppi),
                name: namePtr
            )
            var id: UInt32 = 0
            guard let r = vsc_create(&c, &id), id != kCGNullDirectDisplay else { return nil }
            return (r, id)
        }

        guard let (r, id) = created else {
            ref = nil
            displayID = 0
            config = nil
            return false
        }
        ref = r
        displayID = id
        config = cfg
        return true
    }

    public func destroy() {
        if let r = ref { vsc_destroy(r) }
        ref = nil
        displayID = 0
        config = nil
    }

    /// Live change primitive: destroy + recreate at a new config.
    @discardableResult
    public func reconfigure(_ cfg: VirtualDisplayConfig) -> Bool { create(cfg) }

    deinit { destroy() }
}
