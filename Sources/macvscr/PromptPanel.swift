import AppKit

/// A small centered modal dialog: an icon (centered, top), a message, a text
/// field, an optional control (a checkbox or a 2-option segmented switch), a
/// live preview line that updates as you type or toggle, and OK / Cancel.
///
/// The optional control lets the caller expose a "lock" choice:
///   - checkbox   : "Lock aspect ratio" on/off (used by Width / Height prompts)
///   - segmented  : e.g. "Keep width | Keep height" (used by the Aspect prompt)
final class PromptPanel: NSWindow, NSTextFieldDelegate {

    private let field = NSTextField()
    private let previewLabel = NSTextField(labelWithString: "")
    private var checkbox: NSButton?
    private var segmented: NSSegmentedControl?
    private var previewBuilder: ((String, Bool, Int) -> String?)?
    private var result: String?

    struct Outcome {
        let value: String?
        let checkbox: Bool
        let segment: Int
    }

    /// Show the panel modally.
    /// - `preview` maps (input, checkboxState, segmentIndex) to a result string
    ///   (or nil while invalid) and is re-evaluated live.
    static func run(title: String,
                    message: String,
                    initial: String,
                    checkbox: (label: String, initial: Bool)? = nil,
                    segment: (options: [String], initial: Int)? = nil,
                    preview: @escaping (String, Bool, Int) -> String?) -> Outcome {
        let panel = PromptPanel(title: title, message: message, initial: initial,
                                checkbox: checkbox, segment: segment, preview: preview)
        NSApp.runModal(for: panel)
        panel.close()
        return Outcome(
            value: panel.result,
            checkbox: panel.checkbox.map { $0.state == .on } ?? false,
            segment: panel.segmented.map { Int($0.selectedSegment) } ?? 0
        )
    }

    private init(title: String, message: String, initial: String,
                 checkbox cb: (label: String, initial: Bool)?,
                 segment seg: (options: [String], initial: Int)?,
                 preview: @escaping (String, Bool, Int) -> String?) {
        self.previewBuilder = preview
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 290),
                   styleMask: [.titled], backing: .buffered, defer: false)
        self.title = title
        isReleasedWhenClosed = false
        center()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "display", accessibilityDescription: "macvscr")?
            .withSymbolConfiguration(.init(pointSize: 36, weight: .regular))
        icon.contentTintColor = .controlAccentColor
        icon.frame = NSRect(x: 168, y: 236, width: 44, height: 44)

        let msg = wrappingLabel(message)
        msg.frame = NSRect(x: 30, y: 190, width: 320, height: 36)

        field.stringValue = initial
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.frame = NSRect(x: 70, y: 150, width: 240, height: 24)

        if let cb = cb {
            let b = NSButton(checkboxWithTitle: cb.label, target: self, action: #selector(changed))
            b.state = cb.initial ? .on : .off
            b.sizeToFit()
            var f = b.frame; f.origin.x = (380 - f.width) / 2; f.origin.y = 108; b.frame = f
            checkbox = b
        } else if let seg = seg {
            let s = NSSegmentedControl()
            s.segmentCount = seg.options.count
            for (i, label) in seg.options.enumerated() { s.setLabel(label, forSegment: i) }
            s.selectedSegment = seg.initial
            s.target = self
            s.action = #selector(changed)
            s.frame = NSRect(x: 90, y: 106, width: 200, height: 24)
            segmented = s
        }

        previewLabel.alignment = .center
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.font = .systemFont(ofSize: 12, weight: .medium)
        previewLabel.frame = NSRect(x: 20, y: 74, width: 340, height: 20)

        let cancel = makeButton("Cancel", action: #selector(cancel), key: "\u{1b}")
        cancel.frame = NSRect(x: 196, y: 20, width: 80, height: 26)
        let ok = makeButton("OK", action: #selector(commit), key: "\r", primary: true)
        ok.frame = NSRect(x: 284, y: 20, width: 80, height: 26)

        let cv = contentView!
        for v in [icon, msg, field, previewLabel, cancel, ok] { cv.addSubview(v) }
        if let b = checkbox { cv.addSubview(b) }
        if let s = segmented { cv.addSubview(s) }
        updatePreview()
    }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(field)
        if let ed = field.currentEditor() {
            ed.selectedRange = NSRange(location: 0, length: field.stringValue.count)
        }
    }

    @objc private func changed() { updatePreview() }
    @objc private func commit() { result = field.stringValue; NSApp.stopModal(withCode: .OK) }
    @objc private func cancel() { result = nil; NSApp.stopModal(withCode: .cancel) }

    func controlTextDidChange(_ obj: Notification) { updatePreview() }

    private func updatePreview() {
        let cb = checkbox?.state == .on
        let seg = segmented.map { Int($0.selectedSegment) } ?? 0
        let text = previewBuilder?(field.stringValue, cb, seg) ?? "—"
        previewLabel.stringValue = text.isEmpty ? " " : text
    }

    // MARK: helpers

    private func wrappingLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.isBezeled = false
        l.drawsBackground = false
        l.isEditable = false
        l.isSelectable = false
        l.alignment = .center
        l.font = .systemFont(ofSize: 12)
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 2
        l.cell?.truncatesLastVisibleLine = false
        l.cell?.wraps = true
        return l
    }

    private func makeButton(_ title: String, action: Selector, key: String, primary: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.keyEquivalent = key
        b.bezelStyle = .rounded
        // A return key-equivalent with no modifiers makes this the pulsing default button.
        if primary { b.keyEquivalentModifierMask = [] }
        return b
    }
}
