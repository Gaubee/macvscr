// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtualScreen",
    platforms: [.macOS(.v13)],
    targets: [
        // ObjC++ shim that declares the private CGVirtualDisplay* classes
        // (they live in the public CoreGraphics binary; Apple ships no headers)
        // and exposes a tiny plain-C API to Swift. SPM has no bridging headers,
        // so a separate target with publicHeadersPath is the native pattern.
        .target(
            name: "VSCBridge",
            path: "Sources/VSCBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "macvscr",
            dependencies: ["VSCBridge"],
            path: "Sources/macvscr"
        ),
    ]
)
