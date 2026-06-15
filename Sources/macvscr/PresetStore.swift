import Foundation

/// Singleton store of user-defined presets, persisted to ~/.macvscr/presets.json
/// (reuses ConfigStore's directory + atomic-write pattern). Posts
/// `didChangeNotification` after every mutation so the tray menu and the
/// management window's source list can rebuild.
final class PresetStore {
    static let shared = PresetStore()
    static let didChangeNotification = Notification.Name("macvscr.PresetStoreDidChange")

    private(set) var presets: [CustomPreset] = []

    private static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".macvscr", isDirectory: true)
    }
    private static var fileURL: URL {
        directoryURL.appendingPathComponent("presets.json")
    }

    private init() { load() }

    // MARK: Load / save

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { presets = []; return }
        // Tolerant: any decode failure → empty, never crash the tray.
        presets = (try? JSONDecoder().decode([CustomPreset].self, from: data)) ?? []
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: Mutations

    @discardableResult
    func add(_ p: CustomPreset) -> Int {
        presets.append(p)
        save()
        return presets.count - 1
    }

    func update(_ p: CustomPreset) {
        guard let i = presets.firstIndex(where: { $0.id == p.id }) else { return }
        presets[i] = p
        save()
    }

    func remove(at index: Int) {
        guard presets.indices.contains(index) else { return }
        presets.remove(at: index)
        save()
    }

    func remove(id: UUID) {
        presets.removeAll { $0.id == id }
        save()
    }

    func find(id: UUID) -> CustomPreset? { presets.first { $0.id == id } }
    func findIndex(id: UUID) -> Int? { presets.firstIndex { $0.id == id } }
}
