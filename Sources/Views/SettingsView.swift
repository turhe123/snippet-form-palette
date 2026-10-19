import SwiftUI
import ServiceManagement
import Carbon

/// Preferences: hotkey, date/time formats, behaviour toggles, launch at login and support link.
struct SettingsView: View {
    @AppStorage(Prefs.dateFormat) private var dateFormat = "yyyy-MM-dd"
    @AppStorage(Prefs.timeFormat) private var timeFormat = "HH:mm"
    @AppStorage(Prefs.rememberValues) private var rememberValues = false
    @AppStorage(Prefs.closeAfterPaste) private var closeAfterPaste = true
    @AppStorage(Prefs.restoreClipboard) private var restoreClipboard = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var axTrusted = Paster.hasAccessibility

    var body: some View {
        Form {
            Section("Palette") {
                LabeledContent("Hotkey") { HotKeyRecorder() }
                TextField("Date format", text: $dateFormat)
                Text("Example: \(sample(dateFormat))").font(.caption).foregroundStyle(.secondary)
                TextField("Time format", text: $timeFormat)
                Toggle("Remember last values", isOn: $rememberValues)
                Toggle("Close after paste", isOn: $closeAfterPaste)
                Toggle("Restore original clipboard after paste", isOn: $restoreClipboard)
            }
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                LabeledContent("Accessibility") {
                    if axTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { Paster.requestAccessibility(); Paster.openAccessibilitySettings() }
                    }
                }
                Text("Accessibility permission lets the palette press ⌘V for you. Without it, text is only copied.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            axTrusted = Paster.hasAccessibility
        }
    }

    private func sample(_ format: String) -> String {
        let f = DateFormatter(); f.dateFormat = format; return f.string(from: Date())
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record control for the global palette hotkey.
struct HotKeyRecorder: View {
    @AppStorage(Prefs.hotKeyLabel) private var labelText = "⌥Space"
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : labelText) { recording ? stop() : start() }
            .frame(minWidth: 120)
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let mods = HotKeyManager.carbonModifiers(event.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return nil }
            let d = UserDefaults.standard
            d.set(Int(event.keyCode), forKey: Prefs.hotKeyCode)
            d.set(mods, forKey: Prefs.hotKeyMods)
            labelText = HotKeyManager.label(mods: mods, key: HotKeyManager.keyName(for: event))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyManager.shared.registerFromDefaults()
    }
}
