import SwiftUI
import AppKit

/// Entry point: a menu bar extra plus the template manager and settings windows.
@main
struct SnippetFormPaletteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = TemplateStore.shared

    var body: some Scene {
        MenuBarExtra("SnippetFormPalette", systemImage: "text.badge.plus") {
            MenuContent()
        }
        Window("Manage Templates", id: "manager") {
            ManagerView(store: store)
        }
        Settings {
            SettingsView()
        }
    }
}

/// Items shown in the menu bar dropdown.
struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Palette") { PaletteController.shared.show() }
        Button("Manage Templates…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "manager")
        }
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Support / Donate ❤️") {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
        }
        Divider()
        Button("Quit SnippetFormPalette") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Wires up the global hotkey when the app finishes launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.onPress = { Task { @MainActor in PaletteController.shared.toggle() } }
        HotKeyManager.shared.registerFromDefaults()
    }
}
