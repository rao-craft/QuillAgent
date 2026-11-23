import Foundation

/// One piece of a document's body, in reading order. The model writes these; the kit decides how each looks on the page
/// and in every format.
///
/// Text in `text`, `items`, table cells and field values may carry `**bold**`, `*italic*`, `` `code` `` and
/// `[words](https://…)`; nothing else is markup.
public struct QuillBlock: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A section title: `text`, `level` 1 to 3.
        case heading
        /// A paragraph of `text`.
        case paragraph
        /// `items`, numbered when `ordered`.
        case list
        /// `rows` of cells, the first row the header.
        case table
        /// Words quoted: `text`, said `by` someone the ask or the sources name.
        case quote
        /// A boxed aside: `title` and `text`.
        case callout
        /// A picture at `path` (a file in the project), with `text` as its caption.
        case figure
        /// Label and value rows (`fields`): an invoice's terms, a form's blanks (an empty value is a line to fill in).
        case fields
        /// A line to sign: `text` is the name under it, `by` the title.
        case signature
        /// Code or other text kept as written: `text`.
        case code
        /// A thin line across the column.
        case rule
        /// The next block starts a new page.
        case `break`

        init(loose text: String) {
            let word = text.lowercased().filter { $0.isLetter }
            if let kind = Kind(rawValue: word) { self = kind; return }
            switch word {
            case "title", "section", "subheading", "header", "h", "hone", "htwo", "hthree": self = .heading
            case "bullets", "bullet", "steps", "numbered", "checklist", "items": self = .list
            case "grid", "data", "columns": self = .table
            case "blockquote", "pullquote", "citation": self = .quote
            case "note", "aside", "box", "tip", "warning", "highlight": self = .callout
            case "image", "picture", "photo", "chart", "diagram": self = .figure
            case "form", "blanks", "details", "terms", "keyvalue": self = .fields
            case "sign", "signoff", "signatureline": self = .signature
            case "pre", "monospace", "snippet": self = .code
            case "line", "divider", "separator", "hr": self = .rule
            case "pagebreak", "newpage", "page": self = .break
            default: self = .paragraph
            }
        }
    }

    public struct Field: Codable, Sendable, Equatable {
        public var label: String
        public var value: String

        public init(label: String, value: String = "") { self.label = label; self.value = value }

        private enum Key: String, CodingKey { case label, value }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            label = QuillLoose.text(c, .label) ?? ""
            value = QuillLoose.string(c, .value)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
    }

    public var kind: Kind
    public var text: String?
    public var level: Int?
    public var title: String?
    public var by: String?
    public var path: String?
    public var items: [String]
    public var ordered: Bool?
    public var rows: [[String]]
    public var fields: [Field]

    public init(_ kind: Kind, text: String? = nil, level: Int? = nil, title: String? = nil, by: String? = nil, path: String? = nil,
                items: [String] = [], ordered: Bool? = nil, rows: [[String]] = [], fields: [Field] = []) {
        self.kind = kind; self.text = text; self.level = level; self.title = title; self.by = by; self.path = path
        self.items = items; self.ordered = ordered; self.rows = rows; self.fields = fields
    }

    public static func heading(_ text: String, level: Int = 1) -> QuillBlock { QuillBlock(.heading, text: text, level: level) }
    public static func paragraph(_ text: String) -> QuillBlock { QuillBlock(.paragraph, text: text) }

    private enum Key: String, CodingKey { case kind, text, level, title, by, path, items, ordered, rows, fields }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        kind = QuillLoose.string(c, .kind).map(Kind.init(loose:)) ?? .paragraph
        text = QuillLoose.text(c, .text)
        level = QuillLoose.int(c, .level)
        title = QuillLoose.text(c, .title)
        by = QuillLoose.text(c, .by)?.trimmingCharacters(in: CharacterSet(charactersIn: "-–— "))
        path = QuillLoose.text(c, .path)
        items = QuillLoose.lines(c, .items)
        ordered = QuillLoose.bool(c, .ordered)
        rows = QuillLoose.rows(c, .rows)
        fields = QuillLoose.list(c, .fields, of: Field.self).filter { !$0.label.isEmpty }
        // A code block's text keeps its lines and indents as written.
        if kind == .code { text = QuillLoose.string(c, .text)?.trimmingCharacters(in: .newlines) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(level, forKey: .level)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(by, forKey: .by)
        try c.encodeIfPresent(path, forKey: .path)
        if !items.isEmpty { try c.encode(items, forKey: .items) }
        try c.encodeIfPresent(ordered, forKey: .ordered)
        if !rows.isEmpty { try c.encode(rows, forKey: .rows) }
        if !fields.isEmpty { try c.encode(fields, forKey: .fields) }
    }

    /// The heading level, 1 to 3.
    var depth: Int { min(max(level ?? 1, 1), 3) }

    /// Every word the block shows, for counting and for checking.
    var words: [String] {
        var all = [title, text, by].compactMap { $0 } + items + rows.flatMap { $0 }
        all += fields.flatMap { [$0.label, $0.value] }
        return all.flatMap { $0.split { $0.isWhitespace }.map(String.init) }
    }
}
