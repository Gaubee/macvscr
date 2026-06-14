import AppKit

/// Owns the status item, the live virtual display, and the editable
/// width + aspect + hidpi state (all in LOGICAL pixels). The whole NSMenu is
/// rebuilt on every change so the headline and checkmarks always reflect reality.
///
/// Linking rule: width is the master axis. {height, aspect} are derived from
/// each other through the width:
///   - set width   -> keep aspect, height = width / aspect
///   - set aspect  -> keep width,  height = width / aspect
///   - set height  -> keep width,  aspect = width / height (snaps to standard or custom)
final class TrayController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let display = VirtualDisplay()

    private var logicalWidth: UInt32 = 3440
    private var aspect: Geometry.Aspect = .standard(.w21x9)
    private var hidpi = true

    /// Last successfully applied snapshot (drives the checkmarks).
    private var applied: VirtualDisplayConfig?
    private static let defaultsKey = "macvscr.lastConfig"

    private var logicalHeight: UInt32 { Geometry.height(forWidth: logicalWidth, aspect: aspect) }
    private var physicalWidth: UInt32 { logicalWidth * (hidpi ? 2 : 1) }
    private var physicalHeight: UInt32 { logicalHeight * (hidpi ? 2 : 1) }

    // MARK: Lifecycle

    func start(initial: VirtualDisplayConfig) {
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "macvscr")
        statusItem.button?.image?.isTemplate = true

        logicalWidth = initial.logicalWidth
        aspect = Geometry.aspectFrom(width: initial.logicalWidth, height: initial.logicalHeight)
        hidpi = initial.hidpi

        if display.create(initial) {
            applied = initial
            persist(initial)
        }
        rebuildMenu()
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let head = menu.addItem(
            withTitle: "Active: \(logicalWidth)×\(logicalHeight)\(hidpi ? " @2x" : "")",
            action: nil, keyEquivalent: "")
        head.isEnabled = false

        let phys = menu.addItem(
            withTitle: "Physical: \(physicalWidth)×\(physicalHeight)   ·  \(aspect.label)",
            action: nil, keyEquivalent: "")
        phys.isEnabled = false

        menu.addItem(.separator())

        let presets = menu.addItem(withTitle: "Presets ▸", action: nil, keyEquivalent: "")
        presets.submenu = presetsSubmenu()

        let widths = menu.addItem(withTitle: "Width ▸", action: nil, keyEquivalent: "")
        widths.submenu = widthSubmenu()

        let heights = menu.addItem(withTitle: "Height ▸", action: nil, keyEquivalent: "")
        heights.submenu = heightSubmenu()

        let ratios = menu.addItem(withTitle: "Aspect ▸", action: nil, keyEquivalent: "")
        ratios.submenu = ratioSubmenu()

        let hidpiItem = menu.addItem(withTitle: "HiDPI / Retina @2x", action: #selector(toggleHiDPI), keyEquivalent: "")
        hidpiItem.target = self
        hidpiItem.state = hidpi ? .on : .off

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        statusItem.menu = menu
    }

    private func presetsSubmenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        for p in Presets.all {
            let item = m.addItem(withTitle: p.menuLabel, action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.key
            if isActive(logicalW: p.logicalWidth, logicalH: p.logicalHeight, hidpi: p.hidpi) {
                item.state = .on
            }
        }
        return m
    }

    private func widthSubmenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        for w in Presets.widths {
            let item = m.addItem(withTitle: "\(w)  →  \(w)×\(Geometry.height(forWidth: w, aspect: aspect))",
                                 action: #selector(pickWidth(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Int(w)
            if w == logicalWidth { item.state = .on }
        }
        m.addItem(.separator())
        let c = m.addItem(withTitle: "Custom…", action: #selector(customWidth), keyEquivalent: "")
        c.target = self
        return m
    }

    private func heightSubmenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        for h in Presets.heights {
            let item = m.addItem(withTitle: "\(h)", action: #selector(pickHeight(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Int(h)
            if h == logicalHeight { item.state = .on }
        }
        m.addItem(.separator())
        let c = m.addItem(withTitle: "Custom…", action: #selector(customHeight), keyEquivalent: "")
        c.target = self
        return m
    }

    private func ratioSubmenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        for r in Geometry.Ratio.allCases {
            let h = Geometry.height(forWidth: logicalWidth, aspect: .standard(r))
            let item = m.addItem(withTitle: "\(r.label)  →  \(logicalWidth)×\(h)",
                                 action: #selector(pickRatio(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = r.rawValue
            if case .standard(let cur) = aspect, cur == r { item.state = .on }
        }
        m.addItem(.separator())
        let c = m.addItem(withTitle: "Custom…", action: #selector(customRatio), keyEquivalent: "")
        c.target = self
        return m
    }

    private func isActive(logicalW: UInt32, logicalH: UInt32, hidpi: Bool) -> Bool {
        guard let a = applied else { return false }
        return a.logicalWidth == logicalW && a.logicalHeight == logicalH && a.hidpi == hidpi
    }

    // MARK: Actions

    @objc func applyPreset(_ s: NSMenuItem) {
        guard let key = s.representedObject as? String, let p = Presets.find(key: key) else { return }
        logicalWidth = p.logicalWidth
        aspect = Geometry.aspectFrom(width: p.logicalWidth, height: p.logicalHeight)
        hidpi = p.hidpi
        apply()
    }

    @objc func pickWidth(_ s: NSMenuItem) {
        guard let w = s.representedObject as? Int else { return }
        logicalWidth = UInt32(w); apply()
    }

    @objc func pickHeight(_ s: NSMenuItem) {
        guard let h = s.representedObject as? Int else { return }
        aspect = Geometry.aspectFrom(width: logicalWidth, height: UInt32(h)); apply()
    }

    @objc func pickRatio(_ s: NSMenuItem) {
        guard let raw = s.representedObject as? String, let r = Geometry.Ratio(rawValue: raw) else { return }
        aspect = .standard(r); apply()
    }

    @objc func customWidth() {
        guard let w = promptUInt32(title: "Custom width",
                                   message: "Logical pixels; physical = ×2 when HiDPI",
                                   current: logicalWidth) else { return }
        logicalWidth = w; apply()
    }

    @objc func customHeight() {
        guard let h = promptUInt32(title: "Custom height",
                                   message: "Logical pixels; keeps current width, aspect adjusts",
                                   current: logicalHeight) else { return }
        aspect = Geometry.aspectFrom(width: logicalWidth, height: h); apply()
    }

    @objc func customRatio() {
        guard let a = promptCustomRatio() else { return }
        aspect = a; apply()
    }

    @objc func toggleHiDPI() { hidpi.toggle(); apply() }

    @objc func quit() { display.destroy(); NSApp.terminate(nil) }

    // MARK: Apply

    private func apply() {
        let cfg = VirtualDisplayConfig(logicalWidth: logicalWidth,
                                       logicalHeight: logicalHeight,
                                       hidpi: hidpi,
                                       name: "Virtual Display")
        if display.reconfigure(cfg) {
            applied = cfg
            persist(cfg)
        }
        rebuildMenu()
    }

    // MARK: Prompt dialogs (NSAlert + text field)

    private func promptUInt32(title: String, message: String, current: UInt32) -> UInt32? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = "\(current)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return UInt32(field.stringValue.trimmingCharacters(in: .whitespaces))
    }

    private func promptCustomRatio() -> Geometry.Aspect? {
        let alert = NSAlert()
        alert.messageText = "Custom aspect"
        alert.informativeText = "Enter W:H, e.g. 21:9 or 16:10"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = "21:9"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let parts = field.stringValue.replacingOccurrences(of: " ", with: "").split(separator: ":")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h > 0 else { return nil }
        return Geometry.aspectFrom(factor: w / h)
    }

    // MARK: Persistence

    private func persist(_ cfg: VirtualDisplayConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func loadPersisted() -> VirtualDisplayConfig? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(VirtualDisplayConfig.self, from: data)
    }
}
