import macvscrCore
import AppKit
import SwiftUI

/// Non-modal owner of the "Custom Presets" management window.
///
/// A real macOS document-style window, not a half-built panel:
///   - `[.titled, .resizable, .fullSizeContentView, .closable, .miniaturizable]`
///   - transparent titlebar + hidden title → content flows under the toolbar
///   - the SwiftUI content (a `NavigationSplitView`) provides the sidebar's
///     `.sidebar` vibrancy and the detail pane's translucent material
///     automatically; the window toolbar gets its own `.unified` material.
///   - hosted via `NSHostingController`, non-modal (`showWindow`, not runModal)
///     so the tray keeps working while it is open.
///
/// `TrayController` owns the single instance and supplies:
///   - `library`         — the shared `PresetLibrary` (source of truth)
///   - `liveConfig`      — snapshot of the running display (defaults for Add)
///   - `apply`           — reconfigure the live display to a preset
final class PresetManagerWindowController: NSWindowController {

    private let library: PresetLibrary
    private let liveConfig: () -> (width: UInt32, height: UInt32, hidpi: Bool, dpiPercent: Int?)
    private let apply: (CustomPreset) -> Void
    private let save: (CustomPreset) -> Void
    private let confirm: (CustomPreset) -> Void
    private let revert: () -> Void
    private let preview: PreviewState

    init(library: PresetLibrary,
         preview: PreviewState,
         liveConfig: @escaping () -> (width: UInt32, height: UInt32, hidpi: Bool, dpiPercent: Int?),
         apply: @escaping (CustomPreset) -> Void,
         save: @escaping (CustomPreset) -> Void,
         confirm: @escaping (CustomPreset) -> Void,
         revert: @escaping () -> Void) {
        self.library = library
        self.preview = preview
        self.liveConfig = liveConfig
        self.apply = apply
        self.save = save
        self.confirm = confirm
        self.revert = revert

        let window = EditCommandsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Custom Presets"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 680, height: 420)
        window.setFrameAutosaveName("macvscr.presetManager")
        // Toolbar (its own material, distinct from the sidebar vibrancy).
        let toolbar = NSToolbar(identifier: "macvscr.presetManager")
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        // Keep vibrancy following the system appearance.
        window.appearance = nil

        let view = PresetManagerView(library: library,
                                     preview: preview,
                                     liveConfig: liveConfig,
                                     onApply: apply,
                                     onSave: save,
                                     onConfirm: confirm,
                                     onRevert: revert)
        let hosting = NSHostingController(rootView: view)
        window.contentViewController = hosting

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Show / focus (non-modal; coexists with the .accessory tray app)

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible == true {
            window?.makeKeyAndOrderFront(nil)
        } else {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }
}
