import Foundation
import SwiftUI

/// A reusable text template with a title, tags and a body containing `{{placeholders}}`.
struct Template: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var body: String
    var tags: [String] = []
    var lastUsed: Date?
    var created = Date()
}

/// Owns the template list and persists it as JSON in Application Support.
@MainActor
final class TemplateStore: ObservableObject {
    static let shared = TemplateStore()

    @Published var templates: [Template] = [] { didSet { save() } }
    @Published var lastError: String?

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SnippetFormPalette", isDirectory: true)
            .appendingPathComponent("templates.json")
    }()

    private init() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do { templates = try Self.decoder.decode([Template].self, from: data) }
        catch { lastError = "Could not read templates: \(error.localizedDescription)" }
    }

    /// Templates ordered by most recent use, then alphabetically.
    var recentFirst: [Template] {
        templates.sorted {
            switch ($0.lastUsed, $1.lastUsed) {
            case let (a?, b?): return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    func markUsed(_ id: UUID) {
        if let i = templates.firstIndex(where: { $0.id == id }) { templates[i].lastUsed = Date() }
    }

    func addExamples() { templates.append(contentsOf: Self.examples) }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(templates).write(to: fileURL, options: .atomic)
        } catch { lastError = "Could not save templates: \(error.localizedDescription)" }
    }

    func exportJSON(to url: URL) {
        do { try Self.encoder.encode(templates).write(to: url, options: .atomic) }
        catch { lastError = "Export failed: \(error.localizedDescription)" }
    }

    /// Imports templates from a JSON file, skipping ones whose IDs already exist.
    func importJSON(from url: URL) {
        do {
            let incoming = try Self.decoder.decode([Template].self, from: Data(contentsOf: url))
            let existing = Set(templates.map(\.id))
            templates.append(contentsOf: incoming.filter { !existing.contains($0.id) })
        } catch { lastError = "Import failed: the file is not a valid template export." }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    static let examples: [Template] = [
        Template(title: "Customer reply",
                 body: "Hi {{customer:there}},\n\nThanks for reaching out about order #{{order number}}. {{status|choice(It has shipped,It is being prepared,It has been refunded)}}.\n\nBest regards,\n{{signature:Support Team}}",
                 tags: ["support"]),
        Template(title: "Meeting notes",
                 body: "# {{topic}} — {{@date}}\nAttendees: {{attendees}}\n\n## Notes\n{{notes|multiline}}\n\n## Next meeting\n{{next meeting|date(+7)}}",
                 tags: ["meetings"]),
        Template(title: "Commit message",
                 body: "{{type|choice(feat,fix,docs,refactor,chore):feat}}: {{summary}}\n\n{{details|multiline:}}",
                 tags: ["git", "dev"]),
    ]
}
