import AppKit

/// Owns the status item, the live virtual display, and the editable
/// width + aspect + hidpi state (all in LOGICAL pixels). The whole NSMenu is
/// rebuilt on every change so the headline and checkmarks always reflect reality.
///
/// Linking model (aspect is the lock; either dimension derives the other):
///   - set width   -> keep aspect, height = width  / aspect
///   - set height  -> keep aspect, width  = height * aspect
///   - set aspect  -> keep width,  height = width  / aspect
/// Width and Height submenus list the SAME sizes; they differ only in which
/// dimension is bolded.
final class TrayController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let display = VirtualDisplay()

    private var logicalWidth: UInt32 = 3440
    private var aspect: Geometry.Aspect = .standard(.w21x9)
    private var hidpi = true

    /// Last successfully applied snapshot (drives the checkmarks).
    private var applied: VirtualDisplayConfig?

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

        // NSMenu renders its own submenu disclosure arrow, so no "▸" in titles.
        let presets = menu.addItem(withTitle: "Presets", action: nil, keyEquivalent: "")
        presets.submenu = presetsSubmenu()

        let widths = menu.addItem(withTitle: "Width", action: nil, keyEquivalent: "")
        widths.submenu = widthSubmenu()

        let heights = menu.addItem(withTitle: "Height", action: nil, keyEquivalent: "")
        heights.submenu = heightSubmenu()

        let ratios = menu.addItem(withTitle: "Aspect", action: nil, keyEquivalent: "")
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

    /// Width list: each size with the WIDTH bolded; physical in parens when HiDPI.
    private func widthSubmenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        for w in Presets.widths {
            let h = Geometry.height(forWidth: w, aspect: aspect)
            let item = m.addItem(withTitle: "", action: #selector(pickWidth(_:)), keyEquivalent: "")
            item.attributedTitle = resolutionTitle(w, boldWidth: true, h, hidpi: hidpi)
            item.target = self
            item.representedObject = Int(w)
            if w == logicalWidth { item.state = .on }
        }
        addCustomItem(to: m, action: #selector(customWidth),
                      isPreset: Presets.widths.contains(logicalWidth),
                      value: "\(logicalWidth)")
        return m
    }

    /// Height list: the SAME sizes as Width, but the HEIGHT is bolded.
    private func heightSubmenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        let heightIsPreset = Presets.widths.contains {
            Geometry.height(forWidth: $0, aspect: aspect) == logicalHeight
        }
        for w in Presets.widths {
            let h = Geometry.height(forWidth: w, aspect: aspect)
            let item = m.addItem(withTitle: "", action: #selector(pickHeight(_:)), keyEquivalent: "")
            item.attributedTitle = resolutionTitle(w, boldWidth: false, h, hidpi: hidpi)
            item.target = self
            item.representedObject = Int(h)
            if h == logicalHeight { item.state = .on }
        }
        addCustomItem(to: m, action: #selector(customHeight),
                      isPreset: heightIsPreset,
                      value: "\(logicalHeight)")
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
        let isStandard: Bool
        if case .standard = aspect { isStandard = true } else { isStandard = false }
        addCustomItem(to: m, action: #selector(customRatio),
                      isPreset: isStandard,
                      value: isStandard ? "" : String(format: "%.2f", aspect.factor))
        return m
    }

    /// "W × H" with the picked dimension bolded; physical resolution in dim
    /// parentheses when HiDPI is on.
    private func resolutionTitle(_ w: UInt32, boldWidth: Bool, _ h: UInt32, hidpi: Bool) -> NSAttributedString {
        let base = NSFont.menuFont(ofSize: 0)
        let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        let a = NSMutableAttributedString()
        a.append(NSAttributedString(string: "\(w)", attributes: [.font: boldWidth ? bold : base]))
        a.append(NSAttributedString(string: " × ", attributes: [.font: base]))
        a.append(NSAttributedString(string: "\(h)", attributes: [.font: boldWidth ? base : bold]))
        if hidpi {
            a.append(NSAttributedString(
                string: "  (\(w * 2)×\(h * 2))",
                attributes: [.font: base, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return a
    }

    /// Appends the trailing "Custom…" item. When the current value is not one of
    /// the presets, it is checked and shows the value: "Custom: 3000".
    private func addCustomItem(to menu: NSMenu, action: Selector, isPreset: Bool, value: String) {
        menu.addItem(.separator())
        let title = isPreset ? "Custom…" : (value.isEmpty ? "Custom" : "Custom: \(value)")
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        if !isPreset { item.state = .on }
    }

    private func widthForHeight(_ h: UInt32) -> UInt32 {
        UInt32((Double(h) * aspect.factor).rounded())
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
        logicalWidth = widthForHeight(UInt32(h)); apply()
    }

    @objc func pickRatio(_ s: NSMenuItem) {
        guard let raw = s.representedObject as? String, let r = Geometry.Ratio(rawValue: raw) else { return }
        aspect = .standard(r); apply()
    }

    @objc func customWidth() {
        let aspect = self.aspect
        let hidpi = self.hidpi
        guard let s = PromptPanel.run(
            title: "Custom width",
            message: "Enter a width in logical pixels. Height follows the current aspect ratio.",
            initial: "\(logicalWidth)",
            preview: { input in
                guard let w = UInt32(input.trimmingCharacters(in: .whitespaces)) else { return nil }
                let h = Geometry.height(forWidth: w, aspect: aspect)
                return "\(w) × \(h)\(hidpi ? "  ·  @2x" : "")"
            }) else { return }
        guard let w = UInt32(s.trimmingCharacters(in: .whitespaces)) else { return }
        logicalWidth = w; apply()
    }

    @objc func customHeight() {
        let aspect = self.aspect
        let hidpi = self.hidpi
        guard let s = PromptPanel.run(
            title: "Custom height",
            message: "Enter a height in logical pixels. Width follows the current aspect ratio.",
            initial: "\(logicalHeight)",
            preview: { input in
                guard let h = UInt32(input.trimmingCharacters(in: .whitespaces)) else { return nil }
                let w = UInt32((Double(h) * aspect.factor).rounded())
                return "\(w) × \(h)\(hidpi ? "  ·  @2x" : "")"
            }) else { return }
        guard let h = UInt32(s.trimmingCharacters(in: .whitespaces)) else { return }
        logicalWidth = UInt32((Double(h) * aspect.factor).rounded()); apply()
    }

    @objc func customRatio() {
        let width = self.logicalWidth
        let hidpi = self.hidpi
        guard let s = PromptPanel.run(
            title: "Custom aspect",
            message: "Enter an aspect as W:H (e.g. 21:9). Height is derived from the current width.",
            initial: "21:9",
            preview: { input in
                let parts = input.replacingOccurrences(of: " ", with: "").split(separator: ":")
                guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 else { return nil }
                let h = UInt32((Double(width) / (a / b)).rounded())
                return "\(width) × \(h)\(hidpi ? "  ·  @2x" : "")"
            }) else { return }
        let parts = s.replacingOccurrences(of: " ", with: "").split(separator: ":")
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 else { return }
        aspect = Geometry.aspectFrom(factor: a / b); apply()
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

    // MARK: Persistence (~/.macvscr/config.json)

    private func persist(_ cfg: VirtualDisplayConfig) { ConfigStore.save(cfg) }
    static func loadPersisted() -> VirtualDisplayConfig? { ConfigStore.load() }
}
