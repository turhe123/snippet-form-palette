import SwiftUI
import UniformTypeIdentifiers

/// The template manager window: a list on the left and an editor with a parse report on the right.
struct ManagerView: View {
    @ObservedObject var store: TemplateStore
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.recentFirst) { t in
                    Text(t.title.isEmpty ? "Untitled" : t.title).tag(t.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItemGroup {
                    Button { add() } label: { Label("New", systemImage: "plus") }
                    Button { delete() } label: { Label("Delete", systemImage: "trash") }
                        .disabled(selection == nil)
                    Menu {
                        Button("Import JSON…") { importFile() }
                        Button("Export JSON…") { exportFile() }
                        Button("Add Examples") { store.addExamples() }
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
        } detail: {
            if store.templates.isEmpty {
                VStack(spacing: 12) {
                    Text("No templates yet").font(.title3)
                    Button("Add Three Examples") { store.addExamples() }
                }
            } else if let id = selection, let index = store.templates.firstIndex(where: { $0.id == id }) {
                TemplateEditor(template: $store.templates[index])
            } else {
                Text("Select a template").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .alert("Error", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
    }

    private func add() {
        let t = Template(title: "New Template", body: "Hello {{name}},\n\n")
        store.templates.append(t)
        selection = t.id
    }

    private func delete() {
        guard let id = selection else { return }
        store.templates.removeAll { $0.id == id }
        selection = nil
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { store.importJSON(from: url) }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SnippetFormPalette Templates.json"
        if panel.runModal() == .OK, let url = panel.url { store.exportJSON(to: url) }
    }
}

/// Edits one template's title, tags and body, and shows what the parser detected.
struct TemplateEditor: View {
    @Binding var template: Template
    @State private var parsed = ParsedTemplate()

    private var tagsText: Binding<String> {
        Binding(get: { template.tags.joined(separator: ", ") },
                set: { template.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $template.title).font(.title3).textFieldStyle(.roundedBorder)
            TextField("Tags (comma separated)", text: tagsText).textFieldStyle(.roundedBorder)
            HStack {
                Text("Body").font(.headline)
                Spacer()
                Menu("Insert Placeholder") {
                    Button("Text") { insert("{{name}}") }
                    Button("Text with default") { insert("{{name:default}}") }
                    Button("Multi-line text") { insert("{{notes|multiline}}") }
                    Button("Date (+1 day)") { insert("{{due|date(+1)}}") }
                    Button("Choice") { insert("{{option|choice(A,B,C):A}}") }
                    Divider()
                    Button("Today's date") { insert("{{@date}}") }
                    Button("Current time") { insert("{{@time}}") }
                    Button("Clipboard") { insert("{{@clipboard}}") }
                }
                .fixedSize()
            }
            TextEditor(text: $template.body)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            parseReport
        }
        .padding()
        .task(id: template.body) {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { parsed = PlaceholderParser.parse(template.body) }
        }
    }

    private var parseReport: some View {
        GroupBox("Parse report") {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if parsed.fields.isEmpty { Text("No fields detected.").foregroundStyle(.secondary) }
                    ForEach(parsed.fields) { f in
                        Text("• \(f.name) — \(f.type.rawValue)\(f.options.isEmpty ? "" : " [\(f.options.joined(separator: ", "))]")\(f.defaultValue.map { " (default: “\($0)”)" } ?? "")")
                    }
                    ForEach(Array(parsed.issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 110)
        }
    }

    private func insert(_ token: String) { template.body += token }
}
