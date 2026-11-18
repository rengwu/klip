import Cocoa
import KlipCore

/// Runs a closure as a control's action. Controls hold their target weakly, so the
/// window controller keeps these alive.
private final class Handler: NSObject {
    let run: (NSControl) -> Void
    init(_ run: @escaping (NSControl) -> Void) { self.run = run }
    @objc func fire(_ sender: NSControl) { run(sender) }
}

/// Shows the shortcut; a click records the next key combination. Esc cancels.
private final class ShortcutButton: NSButton {
    var hotKey = HotKey.standard { didSet { title = hotKey.display } }
    var onChange: ((HotKey) -> Bool)?
    private var monitor: Any?

    override func mouseDown(with event: NSEvent) {
        guard monitor == nil else { return stop() }
        title = "Type shortcut…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {  // Esc
                self.stop()
            } else if let key = HotKey(event: event) {
                self.stop()
                if self.onChange?(key) == true { self.hotKey = key } else { NSSound.beep() }
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        title = hotKey.display
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private unowned let app: AppDelegate
    private var handlers: [Handler] = []

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Klip Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        build()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Returning from System Settings may have changed the Accessibility permission.
    func windowDidBecomeKey(_ notification: Notification) {
        build()
    }

    // MARK: Layout

    /// Rebuilding replaces the control whose action is still running, so it waits a turn.
    private func rebuild() {
        DispatchQueue.main.async { [weak self] in self?.build() }
    }

    private func build() {
        guard let window else { return }
        handlers = []
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 9
        grid.columnSpacing = 8

        func row(_ label: String = "", _ views: NSView...) {
            let control: NSView = views.count == 1 ? views[0] : {
                let stack = NSStackView(views: views)
                stack.spacing = 8
                return stack
            }()
            grid.addRow(with: [
                label.isEmpty ? NSGridCell.emptyContentView : NSTextField(labelWithString: label),
                control,
            ])
        }
        func rule() {
            let box = NSBox()
            box.boxType = .separator
            let row = grid.addRow(with: [box])
            row.mergeCells(in: NSRange(location: 0, length: 2))
            row.rowAlignment = .none
            row.topPadding = 5
            row.bottomPadding = 5
            grid.cell(for: box)?.xPlacement = .fill
        }

        let config = app.config
        let shortcut = ShortcutButton(title: "", target: nil, action: nil)
        shortcut.bezelStyle = .rounded
        shortcut.hotKey = config.hotKey
        shortcut.onChange = { [unowned app] in app.setHotKey($0) }
        row("Show panel:", shortcut)

        let login = checkbox("Launch at login", LaunchAtLogin.isEnabled) { [weak self] on in
            do { try LaunchAtLogin.setEnabled(on) } catch { self?.present(error) }
            self?.rebuild()
        }
        // A loose executable cannot be a login item; only the built app can.
        login.isEnabled = LaunchAtLogin.isSupported
        row("", login)
        row("", checkbox("Show in menu bar", config.showMenuBarIcon) { [unowned app] on in
            app.update { $0.showMenuBarIcon = on }
        })
        row("", checkbox("Show key hints in panel", config.showKeyHints) { [unowned app] on in
            app.update { $0.showKeyHints = on }
        })
        row("", checkbox("Show image previews", config.showImagePreview) { [unowned app] on in
            app.update { $0.showImagePreview = on }
        })
        rule()

        let hours = AppConfig.retentionChoices
        row("Keep items for:", popup(
            ["1 hour", "1 day", "3 days", "7 days", "14 days", "30 days"],
            selected: hours.firstIndex(of: config.retentionHours)
        ) { [unowned app] index in app.update { $0.retentionHours = hours[index] } })

        let sizes = AppConfig.sizeChoices
        var used: Int64 = 0
        app.report { used = try app.store.totalBytes() }
        let usedLabel = NSTextField(labelWithString:
            ByteCountFormatter.string(fromByteCount: used, countStyle: .file) + " used")
        usedLabel.font = .systemFont(ofSize: 11)
        usedLabel.textColor = .secondaryLabelColor
        row("Maximum size:", popup(
            ["100 MB", "250 MB", "500 MB", "1 GB", "2 GB"], selected: sizes.firstIndex(of: config.maxBytes)
        ) { [unowned self] index in
            app.update { $0.maxBytes = sizes[index] }
            rebuild()
        }, usedLabel)

        row("", checkbox("Keep text formatting", config.keepFormatting) { [unowned app] on in
            app.update { $0.keepFormatting = on }
        })
        row("", checkbox("Skip passwords", config.skipConcealed) { [unowned app] on in
            app.update { $0.skipConcealed = on }
        })
        row("", button("Clear History…") { [unowned self] in confirmClear() })

        if !Clipboard.canPaste {
            rule()
            row("Paste into apps:", NSTextField(labelWithString: "Not allowed"),
                button("Open Accessibility Settings…") {
                    // Asking adds Klip to the Accessibility list, ready to be switched on.
                    let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                    _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                })
        }

        let content = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
    }

    private func checkbox(_ title: String, _ on: Bool, _ change: @escaping (Bool) -> Void) -> NSButton {
        let handler = Handler { change(($0 as? NSButton)?.state == .on) }
        handlers.append(handler)
        let box = NSButton(checkboxWithTitle: title, target: handler, action: #selector(Handler.fire))
        box.state = on ? .on : .off
        return box
    }

    private func popup(_ titles: [String], selected: Int?, _ change: @escaping (Int) -> Void) -> NSPopUpButton {
        let handler = Handler { change(($0 as? NSPopUpButton)?.indexOfSelectedItem ?? 0) }
        handlers.append(handler)
        let popup = NSPopUpButton()
        popup.addItems(withTitles: titles)
        // A hand-edited value outside the list shows no selection rather than a wrong one.
        popup.selectItem(at: selected ?? -1)
        popup.target = handler
        popup.action = #selector(Handler.fire)
        return popup
    }

    private func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
        let handler = Handler { _ in run() }
        handlers.append(handler)
        return NSButton(title: title, target: handler, action: #selector(Handler.fire))
    }

    private func confirmClear() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned items are kept."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.app.clearHistory()
            self?.build()
        }
    }

    private func present(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
}
