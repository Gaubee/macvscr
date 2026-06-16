import macvscrCore
import AppKit

// Parse CLI args (all pixel values are LOGICAL).
let cli = CLI.parse(Array(CommandLine.arguments.dropFirst()))

// Resolve the initial config: persisted (last run) -> built-in default,
// then apply any explicit CLI overrides.
let base = TrayController.loadPersisted()
    ?? VirtualDisplayConfig(logicalWidth: 3440, logicalHeight: 1440, hidpi: true, name: "Virtual Display")

let logicalWidth = cli.width ?? base.logicalWidth
let ratio = cli.ratio.flatMap { Geometry.Ratio(rawValue: $0) }
let logicalHeight: UInt32
if let r = ratio {
    logicalHeight = Geometry.height(forWidth: logicalWidth, aspect: .standard(r))
} else {
    logicalHeight = cli.height ?? base.logicalHeight
}
let initial = VirtualDisplayConfig(
    logicalWidth: logicalWidth,
    logicalHeight: logicalHeight,
    hidpi: cli.hidpi ?? base.hidpi,
    refreshRate: cli.refresh ?? base.refreshRate,
    name: cli.name ?? base.name
)

// Menu-bar-only agent app: no Dock icon, no main window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.activate(ignoringOtherApps: true)

let tray = TrayController()
tray.start(initial: initial)

app.run()  // blocks; the tray drives everything from here
