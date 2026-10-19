import AppKit
import ApplicationServices

/// Writes text to the pasteboard and simulates ⌘V in the previously active app.
enum Paster {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt so the user can allow synthetic keystrokes.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Pastes `text` into `app`, optionally restoring the original clipboard ~200 ms later.
    static func paste(_ text: String, into app: NSRunningApplication?, restoreClipboard: Bool) {
        let saved = restoreClipboard ? snapshot() : nil
        copy(text)
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            postCommandV()
            if let saved {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { restore(saved) }
            }
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { dict[type] = data } }
            return dict
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let objects = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
    }
}
