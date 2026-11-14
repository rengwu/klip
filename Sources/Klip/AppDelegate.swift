import Cocoa
import KlipCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `KLIP_HOME` points a run at its own data, so checks never touch real history.
    static let directory: URL = {
        if let home = ProcessInfo.processInfo.environment["KLIP_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Klip")
    }()
    private static let configURL = directory.appendingPathComponent("config.json")

    private(set) var config = AppConfig.load(from: AppDelegate.configURL)
    private(set) var store: Store!
    private let hotKeys = HotKeyCenter()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private lazy var panel = PanelController(app: self)
    private lazy var settings = SettingsWindowController(app: self)
    private var lastChangeCount = NSPasteboard.general.changeCount

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try Store(directory: Self.directory)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Klip cannot open its history."
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        installMainMenu()
        installStatusItem()
        hotKeys.action = { [weak self] in self?.panel.toggle() }
        hotKeys.register(config.hotKey)
        prune()

        let poll = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        poll.tolerance = 0.1
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.prune() }

        // For checking a build without the global shortcut: KLIP_SHOW=panel or settings.
        switch ProcessInfo.processInfo.environment["KLIP_SHOW"] {
        case "panel": panel.show()
        case "settings": openSettings()
        default: break
        }
    }

    /// Opening Klip again is the way into Settings when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Capture

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let capture = Clipboard.capture(pasteboard, config: config) else { return }
        report { try store.save(capture, retention: config.retention, maxBytes: config.maxBytes) }
        panel.historyChanged()
    }

    /// Puts an item on the pasteboard without recording it as a new copy.
    func copy(_ content: ItemContent) {
        Clipboard.write(content, to: .general)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func prune() {
        report { try store.prune(retention: config.retention, maxBytes: config.maxBytes) }
    }

    func report(_ work: () throws -> Void) {
        do { try work() } catch { NSLog("Klip: \(error)") }
    }

    // MARK: Settings

    func update(_ change: (inout AppConfig) -> Void) {
        change(&config)
        report { try config.save(to: Self.configURL) }
        statusItem.isVisible = config.showMenuBarIcon
        prune()
        panel.historyChanged()
    }

    /// Changes the shortcut, keeping the previous one when the system refuses the new one.
    func setHotKey(_ key: HotKey) -> Bool {
        guard hotKeys.register(key) else {
            hotKeys.register(config.hotKey)
            return false
        }
        update { $0.hotKey = key }
        return true
    }

    func clearHistory() {
        report { try store.clear() }
        panel.historyChanged()
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settings.show()
    }

    @objc private func showPanel() { panel.show() }

    // MARK: Menus

    private func installStatusItem() {
        statusItem.button?.image = StatusIcon.image()
        statusItem.button?.setAccessibilityLabel("Klip")
        statusItem.isVisible = config.showMenuBarIcon
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Klip", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Klip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// An accessory app has no main menu, which disables ⌘A, C, V, X and Z in text fields:
    /// AppKit routes them through the Edit menu. This restores them for the search field.
    private func installMainMenu() {
        let appMenu = NSMenu(title: "Klip")
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Klip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let mainMenu = NSMenu()
        for menu in [appMenu, editMenu] {
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
    }
}
