import Foundation

/// File-based persistence at ~/.macvscr/config.json (transparent & portable,
/// restored on next launch). Falls back to defaults if missing/unreadable.
enum ConfigStore {
    private static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".macvscr", isDirectory: true)
    }
    private static var fileURL: URL {
        directoryURL.appendingPathComponent("config.json")
    }

    static func load() -> VirtualDisplayConfig? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(VirtualDisplayConfig.self, from: data)
    }

    static func save(_ cfg: VirtualDisplayConfig) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
