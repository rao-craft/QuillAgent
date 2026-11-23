import Foundation

/// A document as one draft (`quill-document/1`): what its first page carries, its style, and its body as blocks. Every
/// format is written from this, and it is kept beside them as `<name>.quill.json`, so a later call writes it again or
/// changes it without drafting from nothing.
///
/// PIN: THE MODEL OWNS THE WORDS, THE KIT OWNS THE PAGE. Nothing here is HTML or a size. A draft says what is written
/// and in what order; how it looks in pages, in Word and in Pages is the kit's and the writers'.
public struct QuillDocument: Codable, Sendable, Equatable {
    public static let format = "quill-document/1"

    public var format: String
    public var form: QuillForm
    /// The title; for a letter, its subject line (or nothing); for a resume, the person's name.
    public var title: String
    /// The line under the title; for a resume, the headline.
    public var subtitle: String?
    public var author: String?
    /// The date as it should read on the page.
    public var date: String?
    /// The sender's lines: a letter's return address, a memo's From, a resume's contact lines.
    public var from: [String]
    /// The recipient's lines: a letter's address, a memo's To.
    public var to: [String]
    public var style: QuillStyle
    public var blocks: [QuillBlock]

    public init(form: QuillForm, title: String, subtitle: String? = nil, author: String? = nil, date: String? = nil,
                from: [String] = [], to: [String] = [], style: QuillStyle = QuillStyle(), blocks: [QuillBlock]) {
        format = Self.format
        self.form = form; self.title = title; self.subtitle = subtitle; self.author = author; self.date = date
        self.from = from; self.to = to; self.style = style; self.blocks = blocks
    }

    private enum Key: String, CodingKey { case format, form, title, subtitle, author, date, from, to, style, blocks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        format = Self.format
        form = QuillLoose.string(c, .form).flatMap(QuillForm.init(loose:)) ?? .report
        title = QuillLoose.text(c, .title) ?? ""
        subtitle = QuillLoose.text(c, .subtitle)
        author = QuillLoose.text(c, .author)
        date = QuillLoose.text(c, .date)
        from = QuillLoose.lines(c, .from)
        to = QuillLoose.lines(c, .to)
        style = (try? c.decodeIfPresent(QuillStyle.self, forKey: .style)) ?? QuillStyle()
        blocks = QuillLoose.list(c, .blocks, of: QuillBlock.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(format, forKey: .format)
        try c.encode(form, forKey: .form)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(date, forKey: .date)
        if !from.isEmpty { try c.encode(from, forKey: .from) }
        if !to.isEmpty { try c.encode(to, forKey: .to) }
        try c.encode(style, forKey: .style)
        try c.encode(blocks, forKey: .blocks)
    }

    /// The face it is set in: the draft's, or its form's.
    var face: QuillFace { style.face ?? form.face }
    var paper: QuillPaper { style.paper ?? .letter }
    /// Numbered headings: the draft's choice, or a contract's clauses.
    var numbered: Bool { style.numbered ?? (form == .contract) }

    /// The words on the page, counted.
    var words: Int {
        let head = [title, subtitle, author, date].compactMap { $0 } + from + to
        return head.flatMap { $0.split { $0.isWhitespace } }.count + blocks.map(\.words.count).reduce(0, +)
    }

    /// The name its files are written under: the title's words, or the form's.
    var slug: String { QuillLoose.slug(title.isEmpty ? form.rawValue : title) }

    /// The draft as kept beside its files: sorted keys, so the same draft is the same bytes.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
