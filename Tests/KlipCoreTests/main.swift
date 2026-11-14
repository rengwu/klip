// KlipCore test runner: `swift run KlipCoreTests`.
// (Executable, not XCTest — this machine has Command Line Tools only.)
import Foundation
import KlipCore

let t = Harness()
let day: TimeInterval = 86_400
let week = 7 * day
let big: Int64 = 500_000_000
let start = Date(timeIntervalSince1970: 1_800_000_000)

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("klip-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeStore() -> (Store, URL) {
    let directory = temporaryDirectory()
    return (try! Store(directory: directory), directory)
}

func titles(_ store: Store, search: String = "", pinnedOnly: Bool = false) -> [String] {
    try! store.page(search: search, pinnedOnly: pinnedOnly).map(\.title)
}

// Order, duplicates and pagination
do {
    let (store, _) = makeStore()
    for (n, word) in ["one", "two", "three"].enumerated() {
        try store.save(.text(word), now: start + Double(n), retention: week, maxBytes: big)
    }
    t.checkEqual(titles(store), ["three", "two", "one"], "newest first")

    let before = try store.page().first { $0.title == "one" }!.id
    let again = try store.save(.text("one"), now: start + 10, retention: week, maxBytes: big)
    t.checkEqual(titles(store), ["one", "three", "two"], "a repeated copy moves to the top")
    t.checkEqual(again, before, "a repeated copy keeps its item")

    t.checkEqual(try store.page(offset: 0, limit: 2).map(\.title), ["one", "three"], "first page")
    t.checkEqual(try store.page(offset: 2, limit: 2).map(\.title), ["two"], "second page")
    t.checkEqual(try store.page(offset: 4, limit: 2).count, 0, "past the end")

    t.check(try store.save(.text(""), now: start, retention: week, maxBytes: big) == nil, "empty copy is not saved")
}

// Search
do {
    let (store, _) = makeStore()
    try store.save(.text("Grüße aus ÖSTERREICH"), now: start, retention: week, maxBytes: big)
    try store.save(.text("first line\nsecond LINE has Needle"), now: start + 1, retention: week, maxBytes: big)
    try store.save(.files(["/Users/a/Downloads/invoice.pdf"]), now: start + 2, retention: week, maxBytes: big)
    try store.save(
        Capture(kind: .image, image: Data([1, 2, 3]), width: 1440, height: 900),
        now: start + 3, retention: week, maxBytes: big)

    t.checkEqual(titles(store, search: "needle"), ["first line"], "matches beyond the first line, any case")
    t.checkEqual(titles(store, search: "österreich"), ["Grüße aus ÖSTERREICH"], "case-insensitive beyond ASCII")
    t.checkEqual(titles(store, search: "downloads"), ["invoice.pdf"], "files match on their path")
    t.checkEqual(titles(store, search: "1440"), ["Image · 1440 × 900"], "images match on their title")
    t.checkEqual(titles(store, search: "100%").count, 0, "wildcard characters are literal")
    t.checkEqual(titles(store, search: "absent").count, 0, "no match")
}

// Titles
do {
    let (store, _) = makeStore()
    try store.save(.text("\n\n   indented first line  \nrest"), now: start, retention: week, maxBytes: big)
    try store.save(.files(["/a/one.txt", "/a/two.txt", "/a/three.txt"]), now: start + 1, retention: week, maxBytes: big)
    t.checkEqual(titles(store), ["3 files", "indented first line"], "titles for text and several files")
    let content = try store.content(id: try store.page()[0].id)!
    t.checkEqual(content.paths, ["/a/one.txt", "/a/two.txt", "/a/three.txt"], "file paths round-trip")
}

// Formatting follows the newest copy
do {
    let (store, _) = makeStore()
    let rtf = Data("{\\rtf1 hello}".utf8)
    let id = try store.save(Capture(kind: .rich, text: "hello", rtf: rtf), now: start, retention: week, maxBytes: big)!
    t.checkEqual(try store.content(id: id)?.rtf, rtf, "formatting is stored")
    t.checkEqual(try store.page()[0].kind, .rich, "kind is rich")
    let same = try store.save(.text("hello"), now: start + 1, retention: week, maxBytes: big)
    t.checkEqual(same, id, "plain and formatted copies of the same text are one item")
    t.check(try store.content(id: id)?.rtf == nil, "a plain copy drops the formatting")
    t.checkEqual(try store.totalBytes(), 5, "size follows the newest copy")
}

// Decay
do {
    let (store, _) = makeStore()
    try store.save(.text("old"), now: start, retention: week, maxBytes: big)
    let pinned = try store.save(.text("old pinned"), now: start, retention: week, maxBytes: big)!
    try store.setPinned(true, id: pinned)
    try store.save(.text("recent"), now: start + 6 * day, retention: week, maxBytes: big)
    try store.prune(now: start + 7 * day + 1, retention: week, maxBytes: big)
    t.checkEqual(titles(store), ["recent", "old pinned"], "decay removes old items but not pinned ones")
    t.checkEqual(titles(store, pinnedOnly: true), ["old pinned"], "pinned-only filter")

    try store.touch(id: try store.page()[0].id, now: start + 8 * day)
    try store.prune(now: start + 14 * day, retention: week, maxBytes: big)
    t.checkEqual(titles(store), ["recent", "old pinned"], "using an item restarts its decay")

    try store.setPinned(false, id: pinned)
    try store.prune(now: start + 14 * day, retention: week, maxBytes: big)
    t.checkEqual(titles(store), ["recent"], "an unpinned item decays again")
}

// Size limit
do {
    let (store, _) = makeStore()
    let limit: Int64 = 1000
    func block(_ character: Character) -> Capture { .text(String(repeating: character, count: 100)) }
    let first = try store.save(block("a"), now: start, retention: week, maxBytes: limit)!
    try store.setPinned(true, id: first)
    for (n, character) in "bcdefghijk".enumerated() {
        try store.save(block(character), now: start + Double(n + 1), retention: week, maxBytes: limit)
    }
    t.checkEqual(try store.totalBytes(), 1000, "a full store is not evicted early")
    try store.save(block("l"), now: start + 20, retention: week, maxBytes: limit)
    let kept = titles(store).map { String($0.prefix(1)) }
    t.checkEqual(kept, ["l", "k", "j", "i", "h", "g", "f", "e", "d", "a"], "the oldest unpinned item is evicted first")

    t.check(
        try store.save(.text(String(repeating: "x", count: 101)), now: start + 30, retention: week, maxBytes: limit) == nil,
        "an item above a tenth of the limit is not saved")
    t.checkEqual(titles(store).count, 10, "a skipped item changes nothing")

    try store.prune(now: start + 30, retention: week, maxBytes: 250)
    t.checkEqual(titles(store).map { String($0.prefix(1)) }, ["l", "a"], "lowering the limit evicts down to it; pins count but stay")
}

// Images, delete and clear
do {
    let (store, directory) = makeStore()
    let images = directory.appendingPathComponent("images")
    func imageFiles() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: images.path).count) ?? -1 }
    let png = Data((0..<64).map { UInt8($0) })
    let id = try store.save(Capture(kind: .image, image: png, width: 8, height: 8), now: start, retention: week, maxBytes: big)!
    let url = try store.content(id: id)!.imageURL!
    t.checkEqual(try Data(contentsOf: url), png, "image data round-trips through its file")
    t.checkEqual(try store.page()[0].imageURL, url, "the summary points at the image file")
    let again = try store.save(Capture(kind: .image, image: png, width: 8, height: 8), now: start + 1, retention: week, maxBytes: big)
    t.checkEqual(again, id, "the same image is one item")
    t.checkEqual(imageFiles(), 1, "one file per image")

    try store.delete(id: id)
    t.checkEqual(imageFiles(), 0, "deleting an item removes its file")

    try store.save(Capture(kind: .image, image: png, width: 8, height: 8), now: start + 2, retention: week, maxBytes: big)
    let keep = try store.save(.text("keep"), now: start + 3, retention: week, maxBytes: big)!
    try store.save(.text("drop"), now: start + 4, retention: week, maxBytes: big)
    try store.setPinned(true, id: keep)
    try store.clear()
    t.checkEqual(titles(store), ["keep"], "clear keeps pinned items")
    t.checkEqual(imageFiles(), 0, "clear removes image files")
    t.checkEqual(try store.totalBytes(), 4, "size after clear")

    // A second store on the same directory sees the same history.
    let reopened = try Store(directory: directory)
    t.checkEqual(titles(reopened), ["keep"], "history persists across launches")
}

// Configuration
do {
    let url = temporaryDirectory().appendingPathComponent("nested/config.json")
    t.checkEqual(AppConfig.load(from: url), AppConfig(), "a missing file yields defaults")
    t.checkEqual(AppConfig().retentionHours, 168, "default decay is 7 days")
    t.checkEqual(AppConfig().maxBytes, 500_000_000, "default size is 500 MB")
    t.checkEqual(AppConfig().hotKey.display, "⇧⌘V", "default shortcut")

    var config = AppConfig()
    config.retentionHours = 24
    config.keepFormatting = false
    config.hotKey = HotKey(keyCode: 8, modifiers: 0x0800, display: "⌥C")
    try config.save(to: url)
    t.checkEqual(AppConfig.load(from: url), config, "settings round-trip")

    try Data(#"{"retentionHours": 99999, "showKeyHints": false}"#.utf8).write(to: url)
    let partial = AppConfig.load(from: url)
    t.checkEqual(partial.retentionHours, 720, "decay is capped at 30 days")
    t.checkEqual(partial.showKeyHints, false, "present keys are read")
    t.checkEqual(partial.maxBytes, 500_000_000, "missing keys take defaults")

    try Data("not json".utf8).write(to: url)
    t.checkEqual(AppConfig.load(from: url), AppConfig(), "a corrupt file yields defaults")
}

t.finish()
