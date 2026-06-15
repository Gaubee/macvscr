import AppKit

/// Two-column split: sidebar (`.sidebar` behavior ⇒ sidebar vibrancy material,
/// automatic) + detail. Lives as the window's contentViewController, so with
/// `.fullSizeContentView` + transparent titlebar the sidebar/titlebar/content
/// materials line up seamlessly.
final class PresetSplitViewController: NSSplitViewController {
    init(source: NSViewController, detail: NSViewController) {
        super.init(nibName: nil, bundle: nil)
        let sidebar = NSSplitViewItem(sidebarWithViewController: source)
        sidebar.canCollapse = false
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 260
        addSplitViewItem(sidebar)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 360
        addSplitViewItem(detailItem)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Singleton owner of the non-modal "Custom Presets" management window.
/// `TrayController` supplies `liveConfigProvider` (defaults for Add) and
/// `applyHandler` (Apply Now). Reopen focuses the existing window.
final class PresetManagerWindowController: NSWindowController {

    static let shared = PresetManagerWindowController()

    /// Defaults a new preset to whatever the display is currently running.
    var liveConfigProvider: (() -> (width: UInt32, height: UInt32, hidpi: Bool))?
    /// Applies a preset to the live display (window stays open).
    var applyHandler: ((CustomPreset) -> Void)?

    private let sourceVC: PresetSourceListViewController
    private let editorVC: PresetEditorViewController

    private init() {
        let source = PresetSourceListViewController()
        let editor = PresetEditorViewController()
        let split = PresetSplitViewController(source: source, detail: editor)
        sourceVC = source
        editorVC = editor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = split
        window.title = "Custom Presets"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 360)
        window.center()

        let toolbar = NSToolbar(identifier: "macvscr.presetManager")
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar

        super.init(window: window)

        // Sidebar → editor binding
        sourceVC.onSelectionChange = { [weak self] index in
            let preset = index.flatMap { PresetStore.shared.presets[$0] }
            self?.editorVC.show(preset: preset)
        }
        sourceVC.onAdd = { [weak self] in self?.addFromWindow() }
        sourceVC.onRemove = { index in PresetStore.shared.remove(at: index) }

        // Editor → store (live) + Apply Now → tray
        editorVC.onChange = { preset in PresetStore.shared.update(preset) }
        editorVC.onApplyNow = { [weak self] preset in self?.applyHandler?(preset) }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Show / focus (non-modal; coexists with the .accessory tray app)

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
        } else {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        }
        // If nothing is selected and there are presets, pick the first row.
        if sourceVC.selectedRow < 0, !PresetStore.shared.presets.isEmpty {
            sourceVC.selectRow(index: 0)
        }
    }

    /// Used by "Add Custom Preset…" from the tray: create from the live config,
    /// then select + focus it for editing.
    func selectAndEdit(index: Int) {
        show()
        sourceVC.selectRow(index: index)
    }

    // MARK: Add

    private func addFromWindow() {
        let live = liveConfigProvider?() ?? (width: 3440 as UInt32, height: 1440 as UInt32, hidpi: true)
        let p = CustomPreset(name: "New Preset",
                             logicalWidth: live.width,
                             logicalHeight: live.height,
                             hidpi: live.hidpi)
        let idx = PresetStore.shared.add(p)
        sourceVC.selectRow(index: idx)
    }
}
