import Carbon.HIToolbox
import Cocoa
import KlipCore

/// One global shortcut through Carbon hot keys, which need no permission.
final class HotKeyCenter {
    var action: () -> Void = {}
    private var hotKey: EventHotKeyRef?

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue().action()
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// Replaces the registered shortcut. False when the system refuses the combination.
    @discardableResult
    func register(_ key: HotKey) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        let id = EventHotKeyID(signature: 0x4B4C_4950, id: 1)  // "KLIP"
        return RegisterEventHotKey(
            key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
}

extension HotKey {
    /// A shortcut from a key press, or nil when it has no ⌘, ⌥ or ⌃ and would shadow typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var modifiers = 0
        var symbols = ""
        if flags.contains(.control) { modifiers |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { modifiers |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { modifiers |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { modifiers |= cmdKey; symbols += "⌘" }
        let named = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        let key = named[Int(event.keyCode)]
            ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(modifiers), display: symbols + key)
    }
}
