import Foundation
import CoreGraphics
import VSCBridge
import macvscrCore

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
                scale: cfg.scale,
                ppi: cfg.ppi,
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
