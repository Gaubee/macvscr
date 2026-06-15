import Foundation

/// A user-defined preset. Source of truth is logical W/H + hidpi (mirrors
/// `VirtualDisplayConfig`'s logical fields). Aspect is derived for display.
struct CustomPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var logicalWidth: UInt32
    var logicalHeight: UInt32
    var hidpi: Bool

    init(id: UUID = UUID(), name: String, logicalWidth: UInt32,
         logicalHeight: UInt32, hidpi: Bool) {
        self.id = id
        self.name = name
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.hidpi = hidpi
    }

    /// Tray label: "My 5K · 2560×1440 @2x"; nameless → plain resolution.
    var menuLabel: String {
        let res = "\(logicalWidth)×\(logicalHeight)\(hidpi ? " @2x" : "")"
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? res : "\(trimmed) · \(res)"
    }

    var aspect: Geometry.Aspect {
        Geometry.aspectFrom(width: logicalWidth, height: logicalHeight)
    }
}
