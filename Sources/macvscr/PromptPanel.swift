import AppKit

/// A small centered modal dialog: an icon (centered, top), a message, a text
/// field, a live preview line that updates as you type, and OK / Cancel.
///
/// Replaces NSAlert for the custom-input prompts so the icon can be centered
/// and the user can see the resulting resolution before confirming.
final class PromptPanel: NSWindow, NSTextFieldDelegate {

    private let field = NSTextField()
    private let previewLabel = NSTextField(labelWithString: "")
    private var previewBuilder: ((String) -> String?)?
    private var result: String?

    /// Show the panel modally. Returns the entered string on OK, nil on cancel.
    /// `preview` maps the current input to a human-readable result string, or
    /// nil while the input is invalid; it updates live as the user types.
    static func run(title: String,
                    message: String,
                    initial: String,
                    preview: @escaping (String) -> String?) -> String? {
        let panel = PromptPanel(title: title, message: message, initial: initial, preview: preview)
        NSApp.runModal(for: panel)
        panel.close()
        return panel.result
    }

    private init(title: String, message: String, initial: String, preview: @escaping (String) -> String?) {
        self.previewBuilder = preview
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 250),
                   styleMask: [.titled],
                   backing: .buffered, defer: false)
        self.title = title
        isReleasedWhenClosed = false
        center()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "display", accessibilityDescription: "macvscr")?
            .withSymbolConfiguration(.init(pointSize: 36, weight: .regular))
        icon.contentTintColor = .controlAccentColor
        icon.frame = NSRect(x: 168, y: 196, width: 44, height: 44)

        let msg = wrappingLabel(message)
        msg.frame = NSRect(x: 30, y: 150, width: 320, height: 36)

        field.stringValue = initial
        field.frame = NSRect(x: 70, y: 112, width: 240, height: 24)
        field.delegate = self
        field.bezelStyle = .roundedBezel

        previewLabel.alignment = .center
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.font = .systemFont(ofSize: 12, weight: .medium)
        previewLabel.frame = NSRect(x: 20, y: 80, width: 340, height: 20)

        let cancel = button("Cancel", action: #selector(cancel), key: "\u{1b}")
        cancel.frame = NSRect(x: 196, y: 20, width: 80, height: 26)
        let ok = button("OK", action: #selector(commit), key: "\r", primary: true)
        ok.frame = NSRect(x: 284, y: 20, width: 80, height: 26)

        for v in [icon, msg, field, previewLabel, cancel, ok] { contentView?.addSubview(v) }
        updatePreview()
    }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: field.stringValue.count)
    }

    @objc private func commit() {
        result = field.stringValue
        NSApp.stopModal(withCode: .OK)
    }
    @objc private func cancel() {
        result = nil
        NSApp.stopModal(withCode: .cancel)
    }

    // MARK: live preview

    func controlTextDidChange(_ obj: Notification) { updatePreview() }
    private func updatePreview() {
        let text = previewBuilder?(field.stringValue) ?? "—"
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

    private func button(_ title: String, action: Selector, key: String, primary: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.keyEquivalent = key
        b.bezelStyle = .rounded
        // A return key-equivalent with no modifiers makes this the pulsing default button.
        if primary { b.keyEquivalentModifierMask = [] }
        return b
    }
}
