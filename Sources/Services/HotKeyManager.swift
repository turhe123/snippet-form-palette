import AppKit
import Carbon

/// Registers a single system-wide hotkey through the Carbon Event Manager.
final class HotKeyManager {
    static let shared = HotKeyManager()
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    /// Registers the hotkey stored in UserDefaults (default ⌥Space).
    func registerFromDefaults() {
        let d = UserDefaults.standard
        let code = d.object(forKey: Prefs.hotKeyCode) as? Int ?? kVK_Space
        let mods = d.object(forKey: Prefs.hotKeyMods) as? Int ?? optionKey
        register(keyCode: UInt32(code), modifiers: UInt32(mods))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x534E_5046), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    /// Converts AppKit modifier flags into Carbon modifier bits.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return m
    }

    /// Human-readable label such as "⌥Space".
    static func label(mods: Int, key: String) -> String {
        var s = ""
        if mods & controlKey != 0 { s += "⌃" }
        if mods & optionKey != 0 { s += "⌥" }
        if mods & shiftKey != 0 { s += "⇧" }
        if mods & cmdKey != 0 { s += "⌘" }
        return s + key
    }

    static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// UserDefaults keys shared across the app.
enum Prefs {
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyMods = "hotKeyMods"
    static let hotKeyLabel = "hotKeyLabel"
    static let dateFormat = "dateFormat"
    static let timeFormat = "timeFormat"
    static let rememberValues = "rememberValues"
    static let closeAfterPaste = "closeAfterPaste"
    static let restoreClipboard = "restoreClipboard"
    static let lastValues = "lastValues"
}
