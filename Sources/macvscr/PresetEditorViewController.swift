import AppKit

/// Right-hand detail editor for a selected `CustomPreset`. An `NSGridView` form
/// on a `.windowBackground` vibrancy backdrop. Editing is live: every change
/// writes through `onChange` (→ PresetStore.update → tray + sidebar rebuild).
/// Stitched linking mirrors TrayController.customWidth/customHeight/customRatio:
///   - width  edit, lock on -> height follows the current aspect
///   - height edit, lock on -> width  follows the current aspect
///   - aspect edit (W:H)     -> keep width, re-derive height
///   - HiDPI / name          -> direct
final class PresetEditorViewController: NSViewController, NSTextFieldDelegate {

    var onChange: ((CustomPreset) -> Void)?
    var onApplyNow: ((CustomPreset) -> Void)?

    private var preset: CustomPreset?

    private let nameField = NSTextField()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let aspectField = NSTextField()
    private let lockCheck = NSButton(checkboxWithTitle: "Lock aspect ratio", target: nil, action: nil)
    private let hidpiCheck = NSButton(checkboxWithTitle: "HiDPI / Retina @2x", target: nil, action: nil)
    private let previewLabel = NSTextField(labelWithString: "")
    private let applyButton = NSButton(title: "Apply Now", target: nil, action: nil)

    private var allFields: [NSControl] {
        [nameField, widthField, heightField, aspectField, lockCheck, hidpiCheck, applyButton]
    }

    override func loadView() {
        // Vibrancy backdrop so the detail pane reads translucent + blurred.
        let backdrop = NSVisualEffectView()
        backdrop.material = .windowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true

        nameField.placeholderString = "Preset name"
        widthField.placeholderString = "3440"
        heightField.placeholderString = "1440"
        aspectField.placeholderString = "W:H, e.g. 21:9"
        for f in [nameField, widthField, heightField, aspectField] {
            f.delegate = self
            f.bezelStyle = .roundedBezel
        }
        lockCheck.target = self; lockCheck.action = #selector(checkToggled)
        hidpiCheck.target = self; hidpiCheck.action = #selector(checkToggled)
        lockCheck.state = .on
        applyButton.target = self; applyButton.action = #selector(applyNow)
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.keyEquivalentModifierMask = []

        previewLabel.font = .systemFont(ofSize: 12, weight: .medium)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.lineBreakMode = .byWordWrapping
        previewLabel.maximumNumberOfLines = 2

        // Form grid
        let grid = NSGridView()
        grid.xPlacement = .leading
        grid.yPlacement = .center
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 10
        grid.rowSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        func labelRow(_ title: String, _ field: NSView) {
            let l = NSTextField(labelWithString: title)
            l.alignment = .right
            l.textColor = .secondaryLabelColor
            l.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            grid.addRow(with: [l, field])
        }
        labelRow("Name", nameField)
        labelRow("Width", widthField)
        labelRow("Height", heightField)
        labelRow("Aspect", aspectField)
        grid.addRow(with: [lockCheck, NSView()])
        grid.addRow(with: [hidpiCheck, NSView()])
        let previewRow = grid.addRow(with: [previewLabel])
        previewRow.mergeCells(in: NSRange(location: 0, length: 2))
        grid.addRow(with: [NSView(), applyButton])

        // Make the field column stretch.
        if grid.numberOfColumns >= 2 {
            grid.column(at: 1).xPlacement = .fill
        }

        backdrop.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -24),
            grid.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])

        view = backdrop
        show(preset: nil)
    }

    // MARK: Binding

    func show(preset: CustomPreset?) {
        self.preset = preset
        let has = preset != nil
        for c in allFields { c.isEnabled = has }
        guard let p = preset else {
            nameField.stringValue = ""
            widthField.stringValue = ""
            heightField.stringValue = ""
            aspectField.stringValue = ""
            hidpiCheck.state = .off
            previewLabel.stringValue = "No preset selected"
            return
        }
        nameField.stringValue = p.name
        widthField.stringValue = "\(p.logicalWidth)"
        heightField.stringValue = "\(p.logicalHeight)"
        aspectField.stringValue = ""
        hidpiCheck.state = p.hidpi ? .on : .off
        updatePreview()
    }

    // MARK: Live updates

    func controlTextDidChange(_ obj: Notification) {
        guard var p = preset else { return }
        let field = obj.object as? NSTextField

        if field == nameField {
            p.name = nameField.stringValue
        } else if field == widthField {
            if let w = UInt32(widthField.stringValue.trimmingCharacters(in: .whitespaces)) {
                let asp = Geometry.aspectFrom(width: p.logicalWidth, height: p.logicalHeight)
                p.logicalWidth = w
                if lockCheck.state == .on {
                    p.logicalHeight = Geometry.height(forWidth: w, aspect: asp)
                    heightField.stringValue = "\(p.logicalHeight)"
                }
            }
        } else if field == heightField {
            if let h = UInt32(heightField.stringValue.trimmingCharacters(in: .whitespaces)) {
                let asp = Geometry.aspectFrom(width: p.logicalWidth, height: p.logicalHeight)
                p.logicalHeight = h
                if lockCheck.state == .on {
                    p.logicalWidth = UInt32((Double(h) * asp.factor).rounded())
                    widthField.stringValue = "\(p.logicalWidth)"
                }
            }
        } else if field == aspectField {
            let parts = aspectField.stringValue.replacingOccurrences(of: " ", with: "").split(separator: ":")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 {
                let f = a / b
                p.logicalHeight = UInt32((Double(p.logicalWidth) / f).rounded())
                heightField.stringValue = "\(p.logicalHeight)"
            }
        } else {
            return
        }
        preset = p
        onChange?(p)
        updatePreview()
    }

    @objc private func checkToggled() {
        guard var p = preset else { return }
        p.hidpi = hidpiCheck.state == .on
        preset = p
        onChange?(p)
        updatePreview()
    }

    @objc private func applyNow() {
        guard let p = preset else { return }
        onApplyNow?(p)
    }

    private func updatePreview() {
        guard let p = preset else { previewLabel.stringValue = "No preset selected"; return }
        let pw = p.logicalWidth * (p.hidpi ? 2 : 1)
        let ph = p.logicalHeight * (p.hidpi ? 2 : 1)
        previewLabel.stringValue =
            "\(p.logicalWidth) × \(p.logicalHeight)\(p.hidpi ? "  @2x" : "")    ·    physical \(pw)×\(ph)    ·    \(reducedRatio(p))"
    }

    private func reducedRatio(_ p: CustomPreset) -> String {
        func gcd(_ a: UInt32, _ b: UInt32) -> UInt32 { b == 0 ? a : gcd(b, a % b) }
        let d = gcd(p.logicalWidth, p.logicalHeight)
        return d > 0 ? "\(p.logicalWidth / d):\(p.logicalHeight / d)" : "—"
    }
}
