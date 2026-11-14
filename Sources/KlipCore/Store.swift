import CryptoKit
import Foundation
import SQLite3

public struct StoreError: Error, CustomStringConvertible {
    public let description: String
}

/// Clipboard history: rows in SQLite, image payloads as PNG files beside it.
/// Not thread-safe; the app uses it from the main thread only.
public final class Store {
    private var db: OpaquePointer?
    private let imagesDirectory: URL

    public init(directory: URL) throws {
        imagesDirectory = directory.appendingPathComponent("images")
        try FileManager.default.createDirectory(
            at: imagesDirectory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("history.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw StoreError(description: "Cannot open \(path): \(message)")
        }
        try run(
            """
            CREATE TABLE IF NOT EXISTS items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              kind TEXT NOT NULL,
              hash BLOB NOT NULL UNIQUE,
              text TEXT NOT NULL,
              search TEXT NOT NULL,
              rtf BLOB,
              html BLOB,
              image TEXT,
              width INTEGER NOT NULL DEFAULT 0,
              height INTEGER NOT NULL DEFAULT 0,
              bytes INTEGER NOT NULL,
              pinned INTEGER NOT NULL DEFAULT 0,
              copied_at REAL NOT NULL
            )
            """)
        try run("CREATE INDEX IF NOT EXISTS items_recent ON items (copied_at DESC, id DESC)")
    }

    deinit { sqlite3_close(db) }

    // MARK: Saving

    /// Stores a copy, or moves the matching item to the top. Returns nil when the copy is
    /// empty or larger than a tenth of `maxBytes`. Applies both limits afterwards.
    @discardableResult
    public func save(
        _ capture: Capture, now: Date = Date(), retention: TimeInterval, maxBytes: Int64
    ) throws -> Int64? {
        let payload = capture.kind == .image ? (capture.image ?? Data()) : Data(capture.text.utf8)
        guard !payload.isEmpty else { return nil }
        let bytes = Int64(payload.count + (capture.rtf?.count ?? 0) + (capture.html?.count ?? 0))
        guard bytes <= maxBytes / 10 else { return nil }

        // Formatting is not part of identity: the same words copied again are the same item.
        var hasher = SHA256()
        hasher.update(data: Data((capture.kind == .rich ? ItemKind.text : capture.kind).rawValue.utf8))
        hasher.update(data: payload)
        let hash = Data(hasher.finalize())

        let id: Int64
        if let existing = try query("SELECT id FROM items WHERE hash = ?", [hash], { $0.int64(0) }).first {
            id = existing
            if capture.kind == .image {
                try run("UPDATE items SET copied_at = ? WHERE id = ?", [now, id])
            } else {
                // The newest copy decides whether the item carries formatting.
                try run(
                    "UPDATE items SET copied_at = ?, kind = ?, rtf = ?, html = ?, bytes = ? WHERE id = ?",
                    [now, capture.kind.rawValue, capture.rtf, capture.html, bytes, id])
            }
        } else {
            var imageName: String?
            if capture.kind == .image {
                let name = hash.map { String(format: "%02x", $0) }.joined() + ".png"
                try payload.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
                imageName = name
            }
            let title = Title.make(
                kind: capture.kind, text: capture.text, width: capture.width, height: capture.height)
            // Images have no text of their own; their title makes them findable.
            let search = (capture.kind == .image ? title : capture.text).lowercased()
            try run(
                """
                INSERT INTO items (kind, hash, text, search, rtf, html, image, width, height, bytes, copied_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    capture.kind.rawValue, hash, capture.text, search, capture.rtf, capture.html,
                    imageName, capture.width, capture.height, bytes, now,
                ])
            id = sqlite3_last_insert_rowid(db)
        }
        try prune(now: now, retention: retention, maxBytes: maxBytes)
        return id
    }

    // MARK: Reading

    /// One page of history, newest first. `search` matches as a case-insensitive substring.
    public func page(
        search: String = "", pinnedOnly: Bool = false, offset: Int = 0, limit: Int = 50
    ) throws -> [ItemSummary] {
        try query(
            """
            SELECT id, kind, substr(text, 1, 2000), width, height, pinned, copied_at, image
            FROM items
            WHERE (?1 = '' OR instr(search, ?1) > 0) AND (?2 = 0 OR pinned = 1)
            ORDER BY copied_at DESC, id DESC LIMIT ?3 OFFSET ?4
            """,
            [search.lowercased(), pinnedOnly ? 1 : 0, limit, offset]
        ) { row in
            let kind = ItemKind(rawValue: row.string(1)) ?? .text
            return ItemSummary(
                id: row.int64(0), kind: kind,
                title: Title.make(
                    kind: kind, text: row.string(2), width: Int(row.int64(3)), height: Int(row.int64(4))),
                pinned: row.int64(5) != 0,
                copiedAt: Date(timeIntervalSince1970: row.double(6)),
                imageURL: row.optionalString(7).map(imagesDirectory.appendingPathComponent))
        }
    }

    public func content(id: Int64) throws -> ItemContent? {
        try query("SELECT kind, text, rtf, html, image FROM items WHERE id = ?", [id]) { row in
            ItemContent(
                kind: ItemKind(rawValue: row.string(0)) ?? .text, text: row.string(1),
                rtf: row.data(2), html: row.data(3),
                imageURL: row.optionalString(4).map(imagesDirectory.appendingPathComponent))
        }.first
    }

    public func totalBytes() throws -> Int64 {
        try query("SELECT COALESCE(SUM(bytes), 0) FROM items", [], { $0.int64(0) }).first ?? 0
    }

    // MARK: Changing

    public func setPinned(_ pinned: Bool, id: Int64) throws {
        try run("UPDATE items SET pinned = ? WHERE id = ?", [pinned ? 1 : 0, id])
    }

    /// Moves an item to the top and restarts its decay.
    public func touch(id: Int64, now: Date = Date()) throws {
        try run("UPDATE items SET copied_at = ? WHERE id = ?", [now, id])
    }

    public func delete(id: Int64) throws {
        try remove(where: "id = ?", [id])
    }

    /// Removes everything that is not pinned.
    public func clear() throws {
        try remove(where: "pinned = 0", [])
    }

    /// Applies decay, then evicts the oldest unpinned items until the store fits `maxBytes`.
    public func prune(now: Date = Date(), retention: TimeInterval, maxBytes: Int64) throws {
        try remove(where: "pinned = 0 AND copied_at < ?", [now.addingTimeInterval(-retention)])
        var excess = try totalBytes() - maxBytes
        guard excess > 0 else { return }
        let oldest = try query(
            "SELECT id, bytes FROM items WHERE pinned = 0 ORDER BY copied_at ASC, id ASC", [],
            { ($0.int64(0), $0.int64(1)) })
        for (id, bytes) in oldest where excess > 0 {
            try delete(id: id)
            excess -= bytes
        }
    }

    private func remove(where condition: String, _ values: [Any?]) throws {
        let images = try query(
            "SELECT image FROM items WHERE image IS NOT NULL AND \(condition)", values,
            { $0.string(0) })
        try run("DELETE FROM items WHERE \(condition)", values)
        for name in images {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    // MARK: SQLite

    private var message: String { String(cString: sqlite3_errmsg(db)) }

    private func run(_ sql: String, _ values: [Any?] = []) throws {
        _ = try query(sql, values) { _ in () }
    }

    private func query<T>(_ sql: String, _ values: [Any?], _ read: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError(description: message)
        }
        defer { sqlite3_finalize(statement) }
        // SQLITE_TRANSIENT: SQLite copies the bytes before the call returns.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case nil: sqlite3_bind_null(statement, index)
            case let v as String: sqlite3_bind_text(statement, index, v, -1, transient)
            case let v as Data:
                _ = v.withUnsafeBytes {
                    sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(v.count), transient)
                }
            case let v as Date: sqlite3_bind_double(statement, index, v.timeIntervalSince1970)
            case let v as Int: sqlite3_bind_int64(statement, index, Int64(v))
            case let v as Int64: sqlite3_bind_int64(statement, index, v)
            default: throw StoreError(description: "Unsupported value: \(String(describing: value))")
            }
        }
        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(read(Row(statement: statement)))
            case SQLITE_DONE: return rows
            default: throw StoreError(description: message)
            }
        }
    }
}

private struct Row {
    let statement: OpaquePointer?

    func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func string(_ column: Int32) -> String { optionalString(column) ?? "" }

    func optionalString(_ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    func data(_ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}
