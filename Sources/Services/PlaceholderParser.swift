import Foundation

/// The kind of input a placeholder asks for.
enum FieldType: String {
    case text, multiline, date, choice
}

/// A single user-fillable placeholder; duplicates by name collapse into one field.
struct Field: Identifiable, Hashable {
    var id: String { name }
    let name: String
    var type: FieldType
    var options: [String] = []
    var defaultValue: String?
    var dayOffset = 0
}

/// Variables filled in automatically when the template is rendered.
enum BuiltIn: Hashable {
    case date(offset: Int), time, clipboard
}

/// One piece of a parsed template body.
enum Segment {
    case literal(String), field(String), builtIn(BuiltIn)
}

/// The result of parsing a template body: segments to render, unique fields and any problems found.
struct ParsedTemplate {
    var segments: [Segment] = []
    var fields: [Field] = []
    var issues: [String] = []
}

/// Parses `{{name|type(args):default}}` placeholders with NSRegularExpression.
///
/// Syntax: `{{name}}`, `{{name:default}}`, `{{name|multiline}}`, `{{name|date(+3)}}`,
/// `{{name|choice(A,B,C):B}}`, and built-ins `{{@date}}`, `{{@date(-1)}}`, `{{@time}}`, `{{@clipboard}}`.
enum PlaceholderParser {
    private static let token = try? NSRegularExpression(pattern: #"\{\{([^{}]*)\}\}"#)
    private static let inner = try? NSRegularExpression(
        pattern: #"^\s*([^|:()]+?)\s*(?:\|\s*(\w+)\s*(?:\(([^)]*)\))?)?\s*(?::(.*))?$"#,
        options: [.dotMatchesLineSeparators])

    static func parse(_ body: String) -> ParsedTemplate {
        var result = ParsedTemplate()
        guard let token, let inner else { return ParsedTemplate(segments: [.literal(body)]) }
        let ns = body as NSString
        var cursor = 0
        var literal = ""

        func flushLiteral(upTo location: Int) {
            guard location > cursor else { return }
            let text = ns.substring(with: NSRange(location: cursor, length: location - cursor))
            reportStrayBraces(in: text, offset: cursor, into: &result.issues)
            literal += text
        }

        for match in token.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            flushLiteral(upTo: match.range.location)
            cursor = match.range.location + match.range.length
            let raw = ns.substring(with: match.range)
            let content = ns.substring(with: match.range(at: 1))
            guard let segment = makeSegment(content, inner: inner, result: &result) else {
                result.issues.append("“\(raw)” is not a valid placeholder and is kept as literal text.")
                literal += raw
                continue
            }
            if !literal.isEmpty { result.segments.append(.literal(literal)); literal = "" }
            result.segments.append(segment)
        }
        flushLiteral(upTo: ns.length)
        if !literal.isEmpty { result.segments.append(.literal(literal)) }
        return result
    }

    private static func makeSegment(_ content: String, inner: NSRegularExpression, result: inout ParsedTemplate) -> Segment? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") { return builtIn(trimmed) }

        let ns = content as NSString
        guard let m = inner.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard let name = group(1), !name.isEmpty else { return nil }
        let typeName = group(2)?.lowercased() ?? "text"
        let args = group(3) ?? ""

        var field = Field(name: name, type: .text, defaultValue: group(4))
        switch typeName {
        case "text": break
        case "multiline": field.type = .multiline
        case "date":
            field.type = .date
            field.dayOffset = Int(args.trimmingCharacters(in: .whitespaces)) ?? 0
        case "choice":
            field.options = args.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if field.options.isEmpty {
                result.issues.append("Choice “\(name)” has no options; using a text input.")
            } else { field.type = .choice }
        default:
            result.issues.append("Unknown type “\(typeName)” for “\(name)”; using a text input.")
        }

        if let i = result.fields.firstIndex(where: { $0.name == name }) {
            if result.fields[i].defaultValue == nil { result.fields[i].defaultValue = field.defaultValue }
        } else {
            result.fields.append(field)
        }
        return .field(name)
    }

    private static func builtIn(_ s: String) -> Segment? {
        let lower = s.lowercased().replacingOccurrences(of: " ", with: "")
        switch lower {
        case "@time": return .builtIn(.time)
        case "@clipboard": return .builtIn(.clipboard)
        case "@date": return .builtIn(.date(offset: 0))
        default:
            guard lower.hasPrefix("@date("), lower.hasSuffix(")"),
                  let n = Int(lower.dropFirst(6).dropLast()) else { return nil }
            return .builtIn(.date(offset: n))
        }
    }

    /// Flags `{{` / `}}` in literal text, which indicates unclosed or nested braces.
    private static func reportStrayBraces(in text: String, offset: Int, into issues: inout [String]) {
        if text.contains("{{") { issues.append("Unclosed or nested “{{” near character \(offset); treated as literal text.") }
        if text.contains("}}") { issues.append("Unmatched “}}” near character \(offset); treated as literal text.") }
    }
}
