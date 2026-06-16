import macvscrCore
import Foundation
import Darwin

/// Parsed CLI options. `nil` means "not specified" so main.swift can fall back
/// to the persisted/last config or the built-in default. All pixel values are
/// LOGICAL pixels (what the UI shows); physical = logical × 2 when HiDPI.
public struct CLIOptions {
    public var width: UInt32?
    public var height: UInt32?
    public var ratio: String?
    public var hidpi: Bool?
    public var refresh: Double?
    public var name: String?
}

/// Hand-rolled parser. Avoids swift-argument-parser, which would fight the
/// AppKit run loop via @main/AsyncParsableCommand.
public enum CLI {
    private static var useColor: Bool { isatty(fileno(stdout)) != 0 }

    public static var usage: String {
        let on = useColor
        let bold = "\u{1B}[1m", cyan = "\u{1B}[36m", dim = "\u{1B}[2m", rst = "\u{1B}[0m"
        func b(_ s: String) -> String { on ? "\(bold)\(s)\(rst)" : s }
        func d(_ s: String) -> String { on ? "\(dim)\(s)\(rst)" : s }
        let title = on ? "\(bold)\(cyan)macvscr\(rst)" : "macvscr"
        return """
        \(title) \(d("— macOS virtual display tray tool"))

        \(b("Usage:")) macvscr [options]
          \(b("--width <px>"))            initial width (logical pixels)
          \(b("--height <px>"))           initial height (logical pixels) (mutually exclusive with --ratio)
          \(b("--ratio <W:H>"))           compute height from width + aspect (16:9, 21:9, …)
          \(b("--hidpi / --no-hidpi"))    Retina @2x on/off (default on)
          \(b("--refresh <Hz>"))          refresh rate (default 60)
          \(b("--name <name>"))           display name prefix
          \(b("-h, --help"))              show this help

        \(d("All pixel values are logical; with HiDPI, physical = logical × 2"))
        \(d("(e.g. 2560×1440 @2x → physical 5120×2880)."))
        \(d("Unspecified options fall back to the last-used setting or the"))
        \(d("built-in default (3440×1440 @2x). After launch, switch resolution /"))
        \(d("ratio / HiDPI live from the menu bar."))
        """
    }

    public static func parse(_ args: [String]) -> CLIOptions {
        var o = CLIOptions()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--width":
                i += 1
                if i < args.count, let v = UInt32(args[i]) { o.width = v }
            case "--height":
                i += 1
                if i < args.count, let v = UInt32(args[i]) { o.height = v }
            case "--ratio":
                i += 1
                if i < args.count { o.ratio = args[i] }
            case "--hidpi":
                o.hidpi = true
            case "--no-hidpi":
                o.hidpi = false
            case "--refresh":
                i += 1
                if i < args.count, let v = Double(args[i]) { o.refresh = v }
            case "--name":
                i += 1
                if i < args.count { o.name = args[i] }
            case "-h", "--help":
                print(usage)
                exit(0)
            default:
                break
            }
            i += 1
        }
        return o
    }
}
