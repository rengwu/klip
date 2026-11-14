import Cocoa
import KlipCore

/// Reading copies from, and writing items back to, the system pasteboard.
enum Clipboard {
    // Markers from nspasteboard.org that password managers set on their copies.
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// The current pasteboard contents as a capture, or nil when there is nothing to keep.
    /// Files win over text, and text wins over an image, when a copy carries several.
    static func capture(_ pasteboard: NSPasteboard, config: AppConfig) -> Capture? {
        let types = pasteboard.types ?? []
        if config.skipConcealed, types.contains(concealed) || types.contains(transient) { return nil }

        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        if let fileURLs, !fileURLs.isEmpty { return .files(fileURLs.map(\.path)) }

        if let text = pasteboard.string(forType: .string), text.contains(where: { !$0.isWhitespace }) {
            guard config.keepFormatting else { return .text(text) }
            let rtf = pasteboard.data(forType: .rtf)
            let html = pasteboard.data(forType: .html)
            return rtf == nil && html == nil
                ? .text(text) : Capture(kind: .rich, text: text, rtf: rtf, html: html)
        }

        let png = pasteboard.data(forType: .png)
        guard let data = png ?? pasteboard.data(forType: .tiff),
            let bitmap = NSBitmapImageRep(data: data),
            let image = png ?? bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return Capture(kind: .image, image: image, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }

    static func write(_ content: ItemContent, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch content.kind {
        case .files:
            pasteboard.writeObjects(content.paths.map { URL(fileURLWithPath: $0) as NSURL })
        case .image:
            if let url = content.imageURL, let data = try? Data(contentsOf: url) {
                pasteboard.setData(data, forType: .png)
            }
        case .text, .rich:
            let item = NSPasteboardItem()
            if let rtf = content.rtf { item.setData(rtf, forType: .rtf) }
            if let html = content.html { item.setData(html, forType: .html) }
            item.setString(content.text, forType: .string)
            pasteboard.writeObjects([item])
        }
    }

    /// Whether Klip may send ⌘V to other apps (the Accessibility permission).
    static var canPaste: Bool { AXIsProcessTrusted() }

    /// Sends ⌘V to the frontmost app.
    static func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: keyDown)  // V
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
