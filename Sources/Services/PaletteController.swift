import AppKit
import SwiftUI

/// A borderless-looking, non-activating floating panel that can still become key for typing.
final class PalettePanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { true }
}

/// Shows and hides the palette panel and remembers which app to return focus to.
@MainActor
final class PaletteController: NSObject, NSWindowDelegate {
    static let shared = PaletteController()
    let model = PaletteModel()
    private var panel: PalettePanel?

    func toggle() { panel?.isVisible == true ? close() : show() }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { model.previousApp = front }
        model.clipboardAtOpen = NSPasteboard.general.string(forType: .string) ?? ""
        model.reset()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel() -> PalettePanel {
        let p = PalettePanel()
        p.delegate = self
        p.contentView = NSHostingView(rootView: PaletteView(model: model, store: TemplateStore.shared))
        return p
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            if !self.model.isPasting { self.close() }
        }
    }
}

/// State and actions for the two-step palette: search, then fill in the form.
@MainActor
final class PaletteModel: ObservableObject {
    @Published var query = ""
    @Published var highlighted = 0
    @Published var template: Template?
    @Published var parsed = ParsedTemplate()
    @Published var values: [String: String] = [:]
    @Published var dates: [String: Date] = [:]
    @Published var toast: String?
    var previousApp: NSRunningApplication?
    var clipboardAtOpen = ""
    var isPasting = false

    private var defaults: UserDefaults { .standard }

    func reset() {
        query = ""; highlighted = 0; template = nil; toast = nil
        parsed = ParsedTemplate(); values = [:]; dates = [:]
    }

    func results(in store: TemplateStore) -> [Template] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let all = store.recentFirst
        guard !q.isEmpty else { return all }
        return all.filter { t in
            t.title.localizedCaseInsensitiveContains(q)
                || t.tags.contains { $0.localizedCaseInsensitiveContains(q) }
                || t.body.prefix(2000).localizedCaseInsensitiveContains(q)
        }
    }

    func choose(_ t: Template) {
        template = t
        parsed = PlaceholderParser.parse(t.body)
        values = [:]; dates = [:]
        let remembered = defaults.bool(forKey: Prefs.rememberValues)
            ? (defaults.dictionary(forKey: Prefs.lastValues) as? [String: String] ?? [:]) : [:]
        for f in parsed.fields {
            switch f.type {
            case .date:
                dates[f.name] = Calendar.current.date(byAdding: .day, value: f.dayOffset, to: Date()) ?? Date()
            case .choice:
                let preferred = remembered[f.name] ?? f.defaultValue ?? ""
                values[f.name] = f.options.contains(preferred) ? preferred : (f.options.first ?? "")
            default:
                values[f.name] = remembered[f.name] ?? ""
            }
        }
    }

    func back() { template = nil; toast = nil }

    func isMissing(_ f: Field) -> Bool {
        f.type != .date && f.defaultValue == nil
            && (values[f.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFinish: Bool { template != nil && !parsed.fields.contains(where: isMissing) }

    /// Produces the final text from segments, field values and built-in variables.
    func render() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = defaults.string(forKey: Prefs.dateFormat) ?? "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = defaults.string(forKey: Prefs.timeFormat) ?? "HH:mm"
        let fieldsByName = Dictionary(parsed.fields.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var out = ""
        for seg in parsed.segments {
            switch seg {
            case .literal(let s): out += s
            case .builtIn(.time): out += timeFormatter.string(from: Date())
            case .builtIn(.clipboard): out += clipboardAtOpen
            case .builtIn(.date(let offset)):
                out += dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date())
            case .field(let name):
                guard let f = fieldsByName[name] else { continue }
                if f.type == .date {
                    out += dateFormatter.string(from: dates[name] ?? Date())
                } else {
                    let v = values[name] ?? ""
                    out += v.isEmpty ? (f.defaultValue ?? "") : v
                }
            }
        }
        return out
    }

    func copyOnly() {
        guard canFinish, let t = template else { return }
        Paster.copy(render())
        finish(t)
        toast = "Copied to clipboard"
    }

    func paste() {
        guard canFinish, let t = template else { return }
        let text = render()
        guard Paster.hasAccessibility else {
            Paster.copy(text)
            finish(t)
            toast = "Copied only — allow Accessibility in System Settings to paste automatically."
            Paster.requestAccessibility()
            return
        }
        finish(t)
        isPasting = true
        let closeAfter = defaults.object(forKey: Prefs.closeAfterPaste) as? Bool ?? true
        if closeAfter { PaletteController.shared.close() } else { reset() }
        Paster.paste(text, into: previousApp, restoreClipboard: defaults.bool(forKey: Prefs.restoreClipboard))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.isPasting = false }
    }

    private func finish(_ t: Template) {
        TemplateStore.shared.markUsed(t.id)
        guard defaults.bool(forKey: Prefs.rememberValues) else { return }
        var stored = defaults.dictionary(forKey: Prefs.lastValues) as? [String: String] ?? [:]
        for f in parsed.fields where f.type != .date { stored[f.name] = values[f.name] }
        defaults.set(stored, forKey: Prefs.lastValues)
    }
}
