import macvscrCore
import AppKit

/// Owns the status item, the live virtual display, and the editable
/// width + aspect + hidpi state (all in LOGICAL pixels). The whole NSMenu is
/// rebuilt on every change so the headline and checkmarks always reflect reality.
///
/// Linking model: by default the aspect ratio is locked, so changing one
/// dimension derives the other. The Custom dialogs can unlock it:
///   - Width / Height Custom : a "Lock aspect ratio" checkbox.
///   - Aspect Custom         : a "Keep width | Keep height" switch.
/// Quick-pick submenus (Width / Height) are always aspect-locked and list the
/// SAME sizes; they differ only in which dimension is bolded.
final class TrayController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let display = VirtualDisplay()

    /// User-defined presets (~/.macvscr/presets.json). Single source of truth
    /// shared with the management window.
    private let library = PresetLibrary()
    private var manager: PresetManagerWindowController?

    private var logicalWidth: UInt32 = 3440
    private var aspect: Geometry.Aspect = .standard(.w21x9)
    private var hidpi = true
    /// DPI scaling % (only meaningful when `hidpi`); `nil` = 200% (default).
    private var dpiPercent: Int? = nil

    /// Last successfully applied (committed) snapshot (drives the checkmarks).
    private var applied: VirtualDisplayConfig?

    /// Global preview state (10s auto-revert). Shared with the management window.
    let preview = PreviewState.shared

    private var logicalHeight: UInt32 { Geometry.height(forWidth: logicalWidth, aspect: aspect) }
    private var scale: Double { hidpi ? Double(dpiPercent ?? 200) / 100 : 1 }
    private var physicalWidth: UInt32 { Geometry.physicalFrom(logical: logicalWidth, scale: scale) }
    private var physicalHeight: UInt32 { Geometry.physicalFrom(logical: logicalHeight, scale: scale) }
    private var densitySuffix: String { hidpi ? Geometry.densitySuffix(scale: scale) : "" }

    // MARK: Lifecycle

    func start(initial: VirtualDisplayConfig) {
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "macvscr")
        statusItem.button?.image?.isTemplate = true

        logicalWidth = initial.logicalWidth
        aspect = Geometry.aspectFrom(width: initial.logicalWidth, height: initial.logicalHeight)
        hidpi = initial.hidpi
        dpiPercent = initial.dpiPercent

        if display.create(initial) {
            applied = initial
            persist(initial)
        }
        rebuildMenu()

        // Keep the tray in sync with user-managed presets, and expose the live
        // config + apply path to the management window.
        NotificationCenter.default.addObserver(self, selector: #selector(presetsChanged),
                                               name: PresetLibrary.didChangeNotification, object: nil)
        manager = PresetManagerWindowController(
            library: library,
            preview: preview,
            liveConfig: { [weak self] in
                self?.currentLiveConfig() ?? (width: 3440, height: 1440, hidpi: true, dpiPercent: nil)
            },
            apply: { [weak self] preset in self?.startPreview(preset) },
            save: { [weak self] preset in self?.library.update(preset) },
            confirm: { [weak self] preset in
                guard let self else { return }
                self.library.update(preset)
                self.commitPreview(preset)
            },
            revert: { [weak self] in self?.revertPreview() })
    }

    @objc private func presetsChanged() { rebuildMenu() }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let head = menu.addItem(
            withTitle: "Active: \(logicalWidth)×\(logicalHeight)\(hidpi ? " " + densitySuffix : "")",
            action: nil, keyEquivalent: "")
        head.isEnabled = false

        let phys = menu.addItem(
            withTitle: physicalHeadline(),
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

        let hidpiItem = menu.addItem(
            withTitle: "HiDPI / Retina\(hidpi ? " " + densitySuffix : "")",
            action: #selector(toggleHiDPI), keyEquivalent: "")
        hidpiItem.target = self
        hidpiItem.state = hidpi ? .on : .off

        // DPI scaling submenu — only meaningful when HiDPI (Retina) is on.
        if hidpi {
            let dpi = menu.addItem(withTitle: "DPI", action: nil, keyEquivalent: "")
            dpi.submenu = dpiSubmenu()
        }

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

        // Custom presets section
        let customs = library.presets
        m.addItem(.separator())
        let header = m.addItem(withTitle: "Custom", action: nil, keyEquivalent: "")
        header.isEnabled = false
        if customs.isEmpty {
            let add = m.addItem(withTitle: "Add Custom Presets…", action: #selector(manageCustomPresets), keyEquivalent: "")
            add.target = self
            add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        } else {
            for c in customs {
                let item = m.addItem(withTitle: c.menuLabel, action: #selector(applyCustomPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = c.id.uuidString
                if isActive(logicalW: c.logicalWidth, logicalH: c.logicalHeight, hidpi: c.hidpi) {
                    item.state = .on
                }
            }
            let manage = m.addItem(withTitle: "Manage Custom Presets…", action: #selector(manageCustomPresets), keyEquivalent: "")
            manage.target = self
            manage.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
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
                      value: isStandard ? "" : reducedRatio())
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
            let pw = Geometry.physicalFrom(logical: w, scale: scale)
            let ph = Geometry.physicalFrom(logical: h, scale: scale)
            a.append(NSAttributedString(
                string: "  (\(pw)×\(ph))",
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

    /// Current resolution as a reduced W:H ratio string (e.g. "43:18"), shown in
    /// the Aspect submenu's Custom item when the aspect isn't a standard ratio.
    private func reducedRatio() -> String {
        Geometry.reducedRatio(width: logicalWidth, height: logicalHeight)
    }

    private func isActive(logicalW: UInt32, logicalH: UInt32, hidpi: Bool) -> Bool {
        guard let a = applied else { return false }
        // Match geometry + that the applied DPI % is the default (200/nil), so a
        // preset only shows checked when density is at its default scaling.
        let dpiIsDefault = (a.dpiPercent ?? 200) == 200
        return a.logicalWidth == logicalW && a.logicalHeight == logicalH && a.hidpi == hidpi && dpiIsDefault
    }

    /// "Physical: W×H · aspect" with an appended "· @NNN%" only when a non-default
    /// DPI scaling is set.
    private func physicalHeadline() -> String {
        var s = "Physical: \(physicalWidth)×\(physicalHeight)   ·  \(aspect.label)"
        if let pct = dpiPercent, pct != 200 { s += "   ·  @\(pct)%" }
        return s
    }

    /// DPI scaling presets (25% steps). 200% = the default.
    private static let dpiPresets: [Int] = [125, 150, 175, 200, 225, 250, 275, 300]

    /// Effective DPI percent (nil → 200).
    private var effectiveDpiPercent: Int { dpiPercent ?? 200 }

    /// PPI for the current config (matches VirtualDisplayConfig.ppi: 109×scale).
    private var currentPPI: Double { hidpi ? 109 * scale : 109 }

    /// Physical screen size in mm for the current config.
    private func screenMM() -> (w: Double, h: Double) {
        let pxPerMM = currentPPI / 25.4
        return (Double(physicalWidth) / pxPerMM, Double(physicalHeight) / pxPerMM)
    }

    /// "logical WxH · NNN ppi · WW×HH cm" for a candidate DPI %, under the
    /// default Keep-Physical behavior (physical px held at the current value).
    private func dpiAnnotation(forPercent pct: Int) -> String {
        let s = Double(pct) / 100
        let ppi = 109 * s
        let lw = Geometry.logicalFrom(physical: physicalWidth, scale: s)
        let lh = Geometry.logicalFrom(physical: physicalHeight, scale: s)
        let pxPerMM = ppi / 25.4
        let wCM = Double(physicalWidth) / pxPerMM / 10
        let hCM = Double(physicalHeight) / pxPerMM / 10
        return "\(lw)×\(lh) · \(Int(ppi)) ppi · \(String(format: "%.1f", wCM))×\(String(format: "%.1f", hCM)) cm"
    }

    private func dpiSubmenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        let cur = effectiveDpiPercent
        for pct in Self.dpiPresets {
            let item = m.addItem(
                withTitle: "\(pct)%   (\(dpiAnnotation(forPercent: pct)))",
                action: #selector(pickDpi(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pct
            if pct == cur { item.state = .on }
        }
        // Custom — checked when the current value isn't one of the presets.
        let isPreset = Self.dpiPresets.contains(cur)
        m.addItem(.separator())
        let title = isPreset ? "Custom…" : "Custom: \(cur)%"
        let custom = m.addItem(withTitle: title, action: #selector(customDpi), keyEquivalent: "")
        custom.target = self
        if !isPreset { custom.state = .on }
        return m
    }

    // MARK: Actions

    @objc func applyPreset(_ s: NSMenuItem) {
        guard let key = s.representedObject as? String, let p = Presets.find(key: key) else { return }
        logicalWidth = p.logicalWidth
        aspect = Geometry.aspectFrom(width: p.logicalWidth, height: p.logicalHeight)
        hidpi = p.hidpi
        dpiPercent = nil   // built-in presets don't carry a DPI %; reset to default
        apply()
    }

    @objc func applyCustomPreset(_ s: NSMenuItem) {
        guard let idStr = s.representedObject as? String,
              let id = UUID(uuidString: idStr),
              let c = library.find(id: id) else { return }
        commitPreview(c) // tray selection = committed, not a timed preview
    }

    @objc func manageCustomPresets() {
        manager?.present()
    }

    /// Snapshot of the currently-applied geometry (defaults for new presets).
    func currentLiveConfig() -> (width: UInt32, height: UInt32, hidpi: Bool, dpiPercent: Int?) {
        (logicalWidth, logicalHeight, hidpi, dpiPercent)
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
        let oldHeight = self.logicalHeight
        let hidpi = self.hidpi
        let suffix = self.densitySuffix
        let res = PromptPanel.run(
            title: "Custom width",
            message: "Enter a width in logical pixels.",
            initial: "\(logicalWidth)",
            checkbox: ("Lock aspect ratio", true),
            preview: { input, lock, _ in
                guard let w = UInt32(input.trimmingCharacters(in: .whitespaces)) else { return nil }
                let h = lock ? Geometry.height(forWidth: w, aspect: aspect) : oldHeight
                return "\(w) × \(h)\(hidpi ? "  ·  " + suffix : "")"
            })
        guard let s = res.value, let w = UInt32(s.trimmingCharacters(in: .whitespaces)) else { return }
        logicalWidth = w
        if !res.checkbox { self.aspect = Geometry.aspectFrom(width: w, height: oldHeight) }
        apply()
    }

    @objc func customHeight() {
        let aspect = self.aspect
        let oldWidth = self.logicalWidth
        let hidpi = self.hidpi
        let suffix = self.densitySuffix
        let res = PromptPanel.run(
            title: "Custom height",
            message: "Enter a height in logical pixels.",
            initial: "\(logicalHeight)",
            checkbox: ("Lock aspect ratio", true),
            preview: { input, lock, _ in
                guard let h = UInt32(input.trimmingCharacters(in: .whitespaces)) else { return nil }
                let w = lock ? UInt32((Double(h) * aspect.factor).rounded()) : oldWidth
                return "\(w) × \(h)\(hidpi ? "  ·  " + suffix : "")"
            })
        guard let s = res.value, let h = UInt32(s.trimmingCharacters(in: .whitespaces)) else { return }
        if res.checkbox {
            logicalWidth = UInt32((Double(h) * aspect.factor).rounded())
        } else {
            self.aspect = Geometry.aspectFrom(width: oldWidth, height: h)
        }
        apply()
    }

    @objc func customRatio() {
        let width = self.logicalWidth
        let height = self.logicalHeight
        let hidpi = self.hidpi
        let suffix = self.densitySuffix
        let res = PromptPanel.run(
            title: "Custom aspect",
            message: "Enter an aspect as W:H (e.g. 21:9).",
            initial: "21:9",
            segment: (["Keep width", "Keep height"], 0),
            preview: { input, _, seg in
                let parts = input.replacingOccurrences(of: " ", with: "").split(separator: ":")
                guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 else { return nil }
                let f = a / b
                if seg == 0 {
                    let h = UInt32((Double(width) / f).rounded())
                    return "\(width) × \(h)\(hidpi ? "  ·  " + suffix : "")"
                } else {
                    let w = UInt32((Double(height) * f).rounded())
                    return "\(w) × \(height)\(hidpi ? "  ·  " + suffix : "")"
                }
            })
        guard let s = res.value else { return }
        let parts = s.replacingOccurrences(of: " ", with: "").split(separator: ":")
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 else { return }
        let f = a / b
        aspect = Geometry.aspectFrom(factor: f)
        if res.segment == 1 { logicalWidth = UInt32((Double(height) * f).rounded()) }
        apply()
    }

    @objc func toggleHiDPI() { hidpi.toggle(); apply() }

    @objc func pickDpi(_ s: NSMenuItem) {
        guard let pct = s.representedObject as? Int else { return }
        // Default behavior = Keep Logical: logical resolution stays; physical
        // pixels re-derive for the new scale.
        dpiPercent = (pct == 200) ? nil : pct
        apply()
    }

    @objc func customDpi() {
        let curPct = effectiveDpiPercent
        let pw = physicalWidth, ph = physicalHeight   // current physical (held if Keep Physical)
        let lw = logicalWidth, lh = logicalHeight     // current logical (held if Keep Logical)
        let res = PromptPanel.run(
            title: "Custom DPI scaling",
            message: "Now:  physical \(pw)×\(ph)\n         logical \(lw)×\(lh)\nEnter 100–400.",
            initial: "\(curPct)",
            segment: (["Keep Physical", "Keep Logical"], 1),
            suffix: "%",
            preview: { input, _, seg in
                guard let pct = Int(input.trimmingCharacters(in: .whitespaces)),
                      (100...400).contains(pct) else { return nil }
                let s = Double(pct) / 100
                let ppi = 109 * s
                let pxPerMM = ppi / 25.4
                // Compute BOTH physical and logical for the candidate scale.
                let (newPW, newPH, newLW, newLH): (UInt32, UInt32, UInt32, UInt32)
                if seg == 0 {
                    // Keep Physical: physical held; logical = physical / scale.
                    newPW = pw; newPH = ph
                    newLW = Geometry.logicalFrom(physical: pw, scale: s)
                    newLH = Geometry.logicalFrom(physical: ph, scale: s)
                } else {
                    // Keep Logical: logical held; physical = logical × scale.
                    newLW = lw; newLH = lh
                    newPW = Geometry.physicalFrom(logical: lw, scale: s)
                    newPH = Geometry.physicalFrom(logical: lh, scale: s)
                }
                // cm is always derived from the (new) physical pixel count.
                let wCM = Double(newPW) / pxPerMM / 10
                let hCM = Double(newPH) / pxPerMM / 10
                return "physical \(newPW)×\(newPH)\nlogical \(newLW)×\(newLH) · \(Int(ppi)) ppi · \(String(format: "%.1f", wCM))×\(String(format: "%.1f", hCM)) cm"
            })
        guard let s = res.value,
              let pct = Int(s.trimmingCharacters(in: .whitespaces)),
              (100...400).contains(pct) else { return }
        let newScale = Double(pct) / 100
        dpiPercent = (pct == 200) ? nil : pct
        if res.segment == 0 {
            // Keep Physical: re-derive logical from the held physical count.
            logicalWidth = Geometry.logicalFrom(physical: pw, scale: newScale)
            aspect = Geometry.aspectFrom(width: logicalWidth,
                                         height: Geometry.logicalFrom(physical: ph, scale: newScale))
        }
        // Keep Logical: logicalWidth/Height unchanged; scale change flows through apply().
        apply()
    }

    @objc func quit() { display.destroy(); NSApp.terminate(nil) }

    // MARK: Apply

    private func apply() {
        let cfg = VirtualDisplayConfig(logicalWidth: logicalWidth,
                                       logicalHeight: logicalHeight,
                                       hidpi: hidpi,
                                       dpiPercent: dpiPercent,
                                       name: "Virtual Display")
        if display.reconfigure(cfg) {
            applied = cfg
            persist(cfg)
        }
        rebuildMenu()
    }

    // MARK: Preview (10s auto-revert, driven from the management window)

    /// Begin / refresh a preview of `p` on the live display. Does NOT persist
    /// and does NOT change the committed config — `applied` is preserved so the
    /// timer can restore it. Re-arming resets the countdown.
    func startPreview(_ p: CustomPreset) {
        preview.active = p
        let cfg = VirtualDisplayConfig(logicalWidth: p.logicalWidth,
                                       logicalHeight: p.logicalHeight,
                                       hidpi: p.hidpi,
                                       dpiPercent: p.dpiPercent,
                                       name: "Virtual Display")
        _ = display.reconfigure(cfg)
        rebuildMenu()
        preview.arm(onExpire: { [weak self] in self?.revertPreview() },
                    onTick:    { [weak self] in self?.preview.objectWillChange.send() })
    }

    /// Revert to the last committed config (timer expiry, or a failed preview).
    func revertPreview() {
        guard let cfg = applied else { preview.clear(); rebuildMenu(); return }
        _ = display.reconfigure(cfg)
        preview.clear()
        rebuildMenu()
    }

    /// Commit the currently-previewed preset (or a given one) as the new
    /// committed config: stops the timer, updates `applied` + persistence.
    func commitPreview(_ p: CustomPreset) {
        logicalWidth = p.logicalWidth
        aspect = Geometry.aspectFrom(width: p.logicalWidth, height: p.logicalHeight)
        hidpi = p.hidpi
        dpiPercent = p.dpiPercent
        preview.clear()
        apply()
    }

    // MARK: Persistence (~/.macvscr/config.json)

    private func persist(_ cfg: VirtualDisplayConfig) { ConfigStore.save(cfg) }
    static func loadPersisted() -> VirtualDisplayConfig? { ConfigStore.load() }
}
