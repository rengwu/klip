import Foundation

public enum ItemKind: String {
    case text, rich, image, files
}

/// One copy, as read from the pasteboard and before it is stored.
public struct Capture {
    public var kind: ItemKind
    /// Plain text; for `.files`, one path per line; empty for `.image`.
    public var text: String
    public var rtf: Data?
    public var html: Data?
    /// PNG data for `.image`.
    public var image: Data?
    public var width: Int
    public var height: Int

    public init(
        kind: ItemKind, text: String = "", rtf: Data? = nil, html: Data? = nil,
        image: Data? = nil, width: Int = 0, height: Int = 0
    ) {
        self.kind = kind
        self.text = text
        self.rtf = rtf
        self.html = html
        self.image = image
        self.width = width
        self.height = height
    }

    public static func text(_ text: String) -> Capture { Capture(kind: .text, text: text) }

    public static func files(_ paths: [String]) -> Capture {
        Capture(kind: .files, text: paths.joined(separator: "\n"))
    }
}

/// What a panel row needs. Never carries the full payload.
public struct ItemSummary: Equatable {
    public let id: Int64
    public let kind: ItemKind
    public let title: String
    public let pinned: Bool
    public let copiedAt: Date
    public let imageURL: URL?
}

/// The full payload, loaded only when an item is pasted.
public struct ItemContent {
    public let kind: ItemKind
    public let text: String
    public let rtf: Data?
    public let html: Data?
    public let imageURL: URL?

    public var paths: [String] { kind == .files ? text.components(separatedBy: "\n") : [] }
}

enum Title {
    /// How many characters of text a row may ever show; also bounds what a page query reads.
    static let limit = 300

    /// The single line a row shows for an item.
    static func make(kind: ItemKind, text: String, width: Int, height: Int) -> String {
        switch kind {
        case .image:
            return "Image · \(width) × \(height)"
        case .files:
            let paths = text.components(separatedBy: "\n")
            return paths.count == 1
                ? (paths[0] as NSString).lastPathComponent : "\(paths.count) files"
        case .text, .rich:
            let line = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            return String(line.prefix(limit))
        }
    }
}
