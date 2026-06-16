import Foundation
import Combine

/// Observable, persisted collection of user-defined custom presets.
///
/// This is the single source of truth for the management window's SwiftUI view
/// (an `ObservableObject`) AND for the tray menu: every mutation persists to
/// `~/.macvscr/presets.json`, publishes to SwiftUI, and posts
/// `didChangeNotification` so `TrayController` can rebuild its Custom section
/// even while the menu is closed.
public final class PresetLibrary: ObservableObject {

    /// Posted after every mutation (observed by `TrayController`).
    public static let didChangeNotification = Notification.Name("macvscr.PresetStoreDidChange")

    @Published private(set) public var presets: [CustomPreset] = []

    private static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".macvscr", isDirectory: true)
    }
    private static var fileURL: URL {
        directoryURL.appendingPathComponent("presets.json")
    }

    public init() { load() }

    // MARK: Load / save

    public func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { presets = []; return }
        // Tolerant: any decode failure → empty, never crash the tray.
        presets = (try? JSONDecoder().decode([CustomPreset].self, from: data)) ?? []
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: Mutations

    /// Append a preset; returns the new preset so callers can select it.
    @discardableResult
    public func append(_ p: CustomPreset) -> CustomPreset {
        presets.append(p)
        persist()
        return p
    }

    /// Replace the preset with the same id, preserving list order.
    public func update(_ p: CustomPreset) {
        guard let i = presets.firstIndex(where: { $0.id == p.id }) else { return }
        presets[i] = p
        persist()
    }

    public func remove(id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    // MARK: Lookup

    public func find(id: UUID) -> CustomPreset? { presets.first { $0.id == id } }
    public func contains(id: UUID) -> Bool { presets.contains { $0.id == id } }
}
