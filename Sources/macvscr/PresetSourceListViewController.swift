import AppKit

/// Left sidebar: a source-list of custom presets + the classic +/- footer bar.
/// Emits selection / add / remove via closures and reloads on store changes.
final class PresetSourceListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    var onSelectionChange: ((Int?) -> Void)?
    var onAdd: (() -> Void)?
    var onRemove: ((Int) -> Void)?

    private let tableView = NSTableView()
    private var removeButton: NSButton!

    private var presets: [CustomPreset] { PresetStore.shared.presets }
    private let cellID = NSUserInterfaceItemIdentifier("presetCell")

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Table
        tableView.addTableColumn(NSTableColumn(identifier: cellID))
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)

        // Footer action bar (+ / −) with sidebar material to blend.
        let footer = NSVisualEffectView()
        footer.material = .sidebar
        footer.blendingMode = .behindWindow
        footer.state = .active
        footer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(footer)

        let addButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!,
                                 target: self, action: #selector(addClicked))
        let removeButton = NSButton(image: NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!,
                                    target: self, action: #selector(removeClicked))
        for b in [addButton, removeButton] {
            b.bezelStyle = .inline
            b.isBordered = false
            b.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(b)
        }
        self.removeButton = removeButton

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),

            addButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 10),
            addButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 6),
            removeButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])

        view = container
        updateRemoveEnabled()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: PresetStore.didChangeNotification, object: nil)
    }

    // MARK: Public

    /// Currently-selected row index, or -1 if none.
    var selectedRow: Int { tableView.selectedRow }

    func selectRow(index: Int?) {
        guard let i = index, presets.indices.contains(i) else {
            tableView.deselectAll(nil)
            onSelectionChange?(nil)
            updateRemoveEnabled()
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        tableView.scrollRowToVisible(i)
        onSelectionChange?(i)
        updateRemoveEnabled()
    }

    // MARK: Actions

    @objc private func addClicked() { onAdd?() }

    @objc private func removeClicked() {
        let i = tableView.selectedRow
        guard i >= 0 else { return }
        onRemove?(i)
    }

    @objc private func storeChanged() {
        let sel = tableView.selectedRow
        tableView.reloadData()
        if sel >= 0, sel < presets.count {
            tableView.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false)
        } else {
            updateRemoveEnabled()
            onSelectionChange?(nil)
        }
    }

    private func updateRemoveEnabled() {
        removeButton?.isEnabled = tableView.selectedRow >= 0
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { presets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let v = (tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView(); c.identifier = cellID
            let tf = NSTextField(labelWithString: ""); tf.textColor = .labelColor; c.textField = tf
            c.addSubview(tf)
            return c
        }()
        let name = presets[row].name.trimmingCharacters(in: .whitespaces)
        v.textField?.stringValue = name.isEmpty ? "Untitled" : name
        return v
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let i = tableView.selectedRow
        updateRemoveEnabled()
        onSelectionChange?(i >= 0 ? i : nil)
    }
}
