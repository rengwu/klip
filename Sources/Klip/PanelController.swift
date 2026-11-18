import Cocoa
import KlipCore

/// A panel that takes keyboard focus without activating Klip, so the app the user was in
/// stays frontmost and receives the paste.
private final class KlipPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKey?(event) == true || super.performKeyEquivalent(with: event)
    }
}

/// The table never has focus (the search field does), so rows would draw the grey
/// unfocused selection. The highlighted row is the panel's live selection.
private final class RowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

/// Keeps the scroller floating over the rows. With "always show scroll bars" set, AppKit
/// would switch to a scroller that reserves a strip on the right and leaves rows off-center.
private final class OverlayScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}

private final class ItemCell: NSTableCellView {
    /// Every kind shares this column, so titles start at the same position on every row.
    let lead = NSImageView()
    let title = NSTextField(labelWithString: "")
    let pin = NSImageView()
    let key = NSTextField(labelWithString: "")
    var itemID: Int64 = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        lead.wantsLayer = true
        lead.layer?.cornerRadius = 3
        lead.layer?.masksToBounds = true
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The title takes the spare width, which keeps the pin and key hint at the trailing edge.
        title.setContentHuggingPriority(.init(1), for: .horizontal)
        pin.setContentHuggingPriority(.required, for: .horizontal)
        key.setContentHuggingPriority(.required, for: .horizontal)
        pin.image = symbol("pin.fill", size: 10)
        pin.contentTintColor = .secondaryLabelColor
        key.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        key.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [lead, title, pin, key])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            lead.widthAnchor.constraint(equalToConstant: 24),
            lead.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private func symbol(_ name: String, size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
}

final class PanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate, NSWindowDelegate {
    private static let pageSize = 50

    private unowned let app: AppDelegate
    private let panel: KlipPanel
    private let search = NSTextField()
    private let table = NSTableView()
    private let scroll = OverlayScrollView()
    private let empty = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let footerRule = NSBox()
    private var listBottom: [NSLayoutConstraint] = []

    private var items: [ItemSummary] = []
    private var exhausted = false
    private var pinnedOnly = false
    private let thumbnails = NSCache<NSURL, NSImage>()
    private let preview = ImagePreview()

    init(app: AppDelegate) {
        self.app = app
        // Titled with a hidden title bar: the system supplies the rounded corners and shadow.
        panel = KlipPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: true)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
        build()
    }

    private func build() {
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        panel.contentView = background

        let glass = NSImageView()
        glass.image = symbol("magnifyingglass", size: 14)
        glass.contentTintColor = .secondaryLabelColor
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.font = .systemFont(ofSize: 15)
        search.delegate = self
        let searchRow = NSStackView(views: [glass, search])
        searchRow.spacing = 8

        let column = NSTableColumn(identifier: .init("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 28
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.allowsEmptySelection = true
        table.refusesFirstResponder = true  // typing always goes to the search field
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
            object: scroll.contentView)

        empty.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        let searchRule = NSBox()
        searchRule.boxType = .separator
        footerRule.boxType = .separator

        for view in [searchRow, searchRule, scroll, empty, footerRule, footer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            searchRow.topAnchor.constraint(equalTo: background.topAnchor, constant: 11),
            searchRow.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            searchRow.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            searchRule.topAnchor.constraint(equalTo: searchRow.bottomAnchor, constant: 10),
            searchRule.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            searchRule.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: searchRule.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            footerRule.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            footerRule.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            footerRule.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -7),
            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
        ])
        // The list ends at the footer, or at the panel's edge when key hints are hidden.
        listBottom = [
            scroll.bottomAnchor.constraint(equalTo: footerRule.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ]
    }

    // MARK: Showing

    func toggle() {
        if panel.isVisible { close() } else { show() }
    }

    func show() {
        search.stringValue = ""
        pinnedOnly = false
        applySettings()
        reload(select: 0)
        // Centered on the screen that holds the keyboard focus.
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
        updatePreview()  // the first row was selected before the panel had its position
    }

    func close() {
        preview.hide()
        panel.orderOut(nil)
    }

    /// Shows the highlighted row's image beside the panel, or hides the preview.
    private func updatePreview() {
        let row = table.selectedRow
        if app.config.showImagePreview, panel.isVisible, items.indices.contains(row),
            let url = items[row].imageURL {
            preview.show(url, beside: panel)
        } else {
            preview.hide()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// New copies and changed settings show up in an open panel.
    func historyChanged() {
        guard panel.isVisible else { return }
        applySettings()
        reload(select: table.selectedRow)
    }

    private func applySettings() {
        let hints = app.config.showKeyHints
        footer.isHidden = !hints
        footerRule.isHidden = !hints
        listBottom[0].isActive = hints
        listBottom[1].isActive = !hints
        // Return only copies until the Accessibility permission lets Klip paste.
        footer.stringValue = [
            Clipboard.canPaste ? "↩ Paste" : "↩ Copy", "⌘P Pin", "⇧⌘P Pinned only", "⌘⌫ Delete",
        ].joined(separator: "     ")
        search.placeholderString = pinnedOnly ? "Search pinned" : "Search"
    }

    // MARK: Data

    /// Reloads from the top, keeping as many rows as were loaded, and highlights `row`.
    private func reload(select row: Int) {
        let count = max(Self.pageSize, items.count)
        items = page(offset: 0, limit: count)
        exhausted = items.count < count
        table.reloadData()
        select(row)
        empty.stringValue = items.isEmpty
            ? (search.stringValue.isEmpty && !pinnedOnly ? "Nothing copied yet" : "No matches") : ""
    }

    private func loadMore() {
        guard !exhausted else { return }
        let more = page(offset: items.count, limit: Self.pageSize)
        exhausted = more.count < Self.pageSize
        items += more
        table.noteNumberOfRowsChanged()
    }

    private func page(offset: Int, limit: Int) -> [ItemSummary] {
        var result: [ItemSummary] = []
        app.report {
            result = try app.store.page(
                search: search.stringValue, pinnedOnly: pinnedOnly, offset: offset, limit: limit)
        }
        return result
    }

    private func select(_ row: Int) {
        defer { updatePreview() }
        guard !items.isEmpty else { return }
        let row = min(max(row, 0), items.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        if row >= items.count - 5 { loadMore() }
    }

    @objc private func scrolled() {
        if scroll.contentView.bounds.maxY > table.frame.height - 200 { loadMore() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? ItemCell ?? ItemCell()
        cell.identifier = id
        let item = items[row]
        cell.itemID = item.id
        cell.lead.imageScaling = .scaleNone
        cell.title.stringValue = item.title
        cell.pin.isHidden = !item.pinned
        cell.key.stringValue = row < 9 ? "⌘\(row + 1)" : ""
        cell.key.isHidden = row >= 9
        switch item.kind {
        case .text: cell.lead.image = symbol("text.alignleft", size: 12)
        case .rich: cell.lead.image = symbol("textformat", size: 12)
        case .files: cell.lead.image = symbol("doc", size: 12)
        case .image:
            cell.lead.image = nil
            if let url = item.imageURL { loadThumbnail(url, into: cell) }
        }
        return cell
    }

    /// Decodes off the main thread; a reused cell only takes the image if it still shows the item.
    private func loadThumbnail(_ url: URL, into cell: ItemCell) {
        cell.lead.imageScaling = .scaleProportionallyUpOrDown
        if let cached = thumbnails.object(forKey: url as NSURL) {
            cell.lead.image = cached
            return
        }
        let id = cell.itemID
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak cell] in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return }
            let thumbnail = NSImage(cgImage: image, size: .zero)
            DispatchQueue.main.async {
                self?.thumbnails.setObject(thumbnail, forKey: url as NSURL)
                if let cell, cell.itemID == id { cell.lead.image = thumbnail }
            }
        }
    }

    // MARK: Actions

    private func paste(_ row: Int) {
        guard items.indices.contains(row) else { return }
        let id = items[row].id
        var content: ItemContent?
        app.report {
            content = try app.store.content(id: id)
            try app.store.touch(id: id)
        }
        guard let content else { return }
        app.copy(content)
        close()
        guard Clipboard.canPaste else { return }
        // Give the previous app's window a moment to take the keyboard back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Clipboard.sendPaste() }
    }

    private func togglePin() {
        let row = table.selectedRow
        guard items.indices.contains(row) else { return }
        app.report { try app.store.setPinned(!items[row].pinned, id: items[row].id) }
        reload(select: row)
    }

    private func deleteSelected() {
        let row = table.selectedRow
        guard items.indices.contains(row) else { return }
        app.report { try app.store.delete(id: items[row].id) }
        reload(select: row)
    }

    @objc private func clicked() {
        paste(table.clickedRow)
    }

    func controlTextDidChange(_ notification: Notification) {
        items = []
        reload(select: 0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): select(table.selectedRow + 1)
        case #selector(NSResponder.moveUp(_:)): select(table.selectedRow - 1)
        case #selector(NSResponder.insertNewline(_:)): paste(table.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == [.command, .shift], character == "p" {
            pinnedOnly.toggle()
            applySettings()
            items = []
            reload(select: 0)
            return true
        }
        guard modifiers == .command else { return false }
        if event.keyCode == 51 {  // ⌫
            deleteSelected()
        } else if character == "p" {
            togglePin()
        } else if character == "," {
            close()
            app.openSettings()
        } else if let digit = Int(character), (1...9).contains(digit) {
            paste(digit - 1)
        } else {
            return false
        }
        return true
    }
}
