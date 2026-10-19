import SwiftUI

/// The floating palette: a searchable template list, then a dynamic form with live preview.
struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @ObservedObject var store: TemplateStore

    var body: some View {
        VStack(spacing: 0) {
            if let t = model.template { formStep(t) } else { searchStep }
            if let toast = model.toast {
                HStack {
                    Image(systemName: "info.circle")
                    Text(toast).font(.callout)
                    Spacer()
                    if !Paster.hasAccessibility {
                        Button("Open Settings") { Paster.openAccessibilitySettings() }
                    }
                }
                .padding(10)
                .background(.yellow.opacity(0.2))
            }
            Button("") { model.template == nil ? PaletteController.shared.close() : model.back() }
                .keyboardShortcut(.cancelAction).hidden().frame(height: 0)
        }
        .frame(width: 520, height: 420)
        .background(.regularMaterial)
    }

    // MARK: Step 1 — search

    private var searchStep: some View {
        let results = model.results(in: store)
        return VStack(spacing: 0) {
            TextField("Search templates…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(14)
                .onSubmit { if results.indices.contains(model.highlighted) { model.choose(results[model.highlighted]) } }
                .onKeyPress(.downArrow) { model.highlighted = min(model.highlighted + 1, results.count - 1); return .handled }
                .onKeyPress(.upArrow) { model.highlighted = max(model.highlighted - 1, 0); return .handled }
                .onChange(of: model.query) { model.highlighted = 0 }
            Divider()
            if store.templates.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text("No templates yet").font(.headline)
                    Button("Add Three Examples") { store.addExamples() }
                    Spacer()
                }
            } else if results.isEmpty {
                Spacer(); Text("No matches").foregroundStyle(.secondary); Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(Array(results.enumerated()), id: \.element.id) { index, t in
                        row(t, selected: index == model.highlighted)
                            .id(t.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.choose(t) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: model.highlighted) {
                        if results.indices.contains(model.highlighted) { proxy.scrollTo(results[model.highlighted].id) }
                    }
                }
            }
        }
    }

    private func row(_ t: Template, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title.isEmpty ? "Untitled" : t.title).font(.body.weight(.medium))
                Text(t.body.prefix(80).replacingOccurrences(of: "\n", with: " "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            ForEach(t.tags, id: \.self) { tag in
                Text(tag).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
    }

    // MARK: Step 2 — form + preview

    private func formStep(_ t: Template) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.back() } label: { Label("Back", systemImage: "chevron.left") }
                Text(t.title).font(.headline).lineLimit(1)
                Spacer()
            }
            .padding(10)
            Divider()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.parsed.fields.isEmpty {
                            Text("This template has no fields.").foregroundStyle(.secondary)
                        }
                        ForEach(model.parsed.fields) { field in fieldInput(field) }
                    }
                    .padding(12)
                }
                .frame(width: 260)
                Divider()
                ScrollView {
                    Text(model.render())
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            Divider()
            HStack {
                Text("⌘↩ paste · ⌥↩ copy").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { model.copyOnly() }
                    .keyboardShortcut(.return, modifiers: .option)
                Button("Paste") { model.paste() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .disabled(!model.canFinish)
            .padding(10)
        }
    }

    @ViewBuilder
    private func fieldInput(_ f: Field) -> some View {
        let missing = model.isMissing(f)
        let text = Binding(get: { model.values[f.name] ?? "" }, set: { model.values[f.name] = $0 })
        VStack(alignment: .leading, spacing: 4) {
            Text(f.name.capitalized).font(.caption.weight(.semibold))
                .foregroundStyle(missing ? .red : .secondary)
            switch f.type {
            case .text:
                TextField(f.defaultValue ?? "Required", text: text)
                    .textFieldStyle(.roundedBorder)
            case .multiline:
                TextEditor(text: text)
                    .font(.body)
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            case .date:
                DatePicker("", selection: Binding(get: { model.dates[f.name] ?? Date() },
                                                  set: { model.dates[f.name] = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
            case .choice:
                Picker("", selection: text) {
                    ForEach(f.options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).stroke(missing ? Color.red.opacity(0.7) : .clear))
    }
}
