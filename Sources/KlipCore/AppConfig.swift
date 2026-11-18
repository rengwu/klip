import Foundation

/// A global shortcut: a virtual key code, Carbon modifier flags, and the text shown for it.
public struct HotKey: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var display: String

    public init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// ⇧⌘V: key code 9, Carbon `cmdKey | shiftKey`.
    public static let standard = HotKey(keyCode: 9, modifiers: 0x0100 | 0x0200, display: "⇧⌘V")
}

public struct AppConfig: Codable, Equatable {
    public static let retentionChoices = [1, 24, 72, 168, 336, 720]
    public static let sizeChoices: [Int64] = [100, 250, 500, 1000, 2000].map { $0 * 1_000_000 }

    public var retentionHours = 168
    public var maxBytes: Int64 = 500_000_000
    public var keepFormatting = true
    public var skipConcealed = true
    public var showMenuBarIcon = true
    public var showKeyHints = true
    public var showImagePreview = true
    public var hotKey = HotKey.standard

    public init() {}

    public var retention: TimeInterval { TimeInterval(retentionHours) * 3600 }

    /// Missing keys take their defaults, so older files keep loading as settings are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        let hours = try c.decodeIfPresent(Int.self, forKey: .retentionHours) ?? d.retentionHours
        retentionHours = min(max(hours, 1), 720)
        maxBytes = max(try c.decodeIfPresent(Int64.self, forKey: .maxBytes) ?? d.maxBytes, 1_000_000)
        keepFormatting = try c.decodeIfPresent(Bool.self, forKey: .keepFormatting) ?? d.keepFormatting
        skipConcealed = try c.decodeIfPresent(Bool.self, forKey: .skipConcealed) ?? d.skipConcealed
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        showKeyHints = try c.decodeIfPresent(Bool.self, forKey: .showKeyHints) ?? d.showKeyHints
        showImagePreview = try c.decodeIfPresent(Bool.self, forKey: .showImagePreview) ?? d.showImagePreview
        hotKey = try c.decodeIfPresent(HotKey.self, forKey: .hotKey) ?? d.hotKey
    }

    /// An unreadable or absent file yields the defaults.
    public static func load(from url: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
