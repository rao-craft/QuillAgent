import Foundation

/// What the model is told: the house rules, each form's shape, an example from somewhere else entirely, and the schema
/// its JSON must fit.
///
/// PIN: THE EXAMPLE IS A STRANGER'S. It is a bakery's memo, so a draft that copies its words is caught (`echoes`) and
/// never mistaken for the person's.
enum QuillPrompt {
    static func rules(today: String) -> String {
        """
        You write documents for a layout engine, as one JSON object that fits the schema. You write the words; the engine \
        sets the type, the page and every file, so never write HTML, CSS, Markdown headings (#), sizes or page numbers.

        Blocks, in reading order: heading (text, level 1-3), paragraph (text), list (items, ordered), table (rows: the \
        first row is the header), quote (text, by), callout (title, text), figure (path of a picture the person named, \
        text as its caption), fields (label and value rows; an empty value is a blank to fill in), signature (text is the \
        name under the line, by the title), code (text), rule, break (the next block starts a new page).
        Inside text you may use **bold**, *italic*, `code` and [words](https://address), nothing else.

        Facts: use only what the brief and the sources give. Never invent a person, company, address, email, phone, \
        date, figure, price, percentage or quote. Where the document needs one that was not given, write a bracketed \
        placeholder the person will fill in, such as [Hiring Manager's Name], [Company Address], [Phone] or [figure]. \
        A quote's `by` is only a person the brief or sources name. Today is \(today); a letter or memo may carry that date.

        Write as a skilled professional writer would for the form: plain, specific, warm where it suits, no filler, no \
        clichés, no headings in a letter. Keep to what the person asked for.
        """
    }

    static func shape(_ form: QuillForm) -> String {
        switch form {
        case .letter:
            return "A letter: `from` is the sender's lines (name, address, email, phone) as given; `to` is the recipient's lines; `date`; `title` is a subject line or empty. Blocks: a salutation paragraph (\"Dear …,\"), three to five paragraphs, a closing paragraph (\"Sincerely,\"), and a signature block with the sender's name. No headings."
        case .memo:
            return "A memo: `to`, `from` and `date`; `title` is the subject. Blocks: short paragraphs, a heading only where it helps, a list for actions or decisions."
        case .resume:
            return "A resume: `title` is the person's name, `subtitle` their headline, `from` their contact lines. Blocks: level 1 headings for sections (Summary, Experience, Education, Skills); for each role a level 2 heading (role, company) and a level 3 heading (dates, place) followed by a list of achievements, each one line."
        case .report:
            return "A report: `title`, `subtitle`, `author`, `date`. Blocks: level 1 headings for sections, level 2 inside them; paragraphs; lists; tables for figures; a callout for the key finding."
        case .proposal:
            return "A proposal: `title`, `subtitle`, `to` (who it is for), `author`, `date`. Blocks: level 1 headings for the problem, the approach, the scope, the timeline, the cost and the next step; a table for prices or milestones."
        case .contract:
            return "A contract: `title`, `date`. Blocks: a paragraph naming the parties, a level 1 heading for each clause with its paragraphs, fields for the parties' details, and a signature block for each party at the end."
        case .worksheet:
            return "A worksheet: `title`, `subtitle`. Blocks: a paragraph of instructions, an ordered list of questions or steps, and fields where answers are written."
        case .onepager:
            return "A one-pager: `title`, `subtitle`. Blocks: a short opening paragraph, two or three level 1 headings each with a short paragraph or list, a callout for the one thing to remember. It must fit on one page."
        }
    }

    /// A stranger's document: a bakery's memo.
    static let example = """
    Example of the JSON (for a different person and subject; never copy its words):
    {"form":"memo","title":"Oven rota for the Bramblewick bakery","to":["Bramblewick bakers"],"from":["Odile Fenn"],"date":"[Date]",\
    "blocks":[{"kind":"paragraph","text":"From Monday the **stone oven** is fired at five, not six."},\
    {"kind":"list","items":["Sourdough first, rye second","Croissants once the deck cools to 200°"]},\
    {"kind":"callout","title":"Ask","text":"Write your shift on the rota by [day]."}]}
    """

    /// Words of the example a draft should never carry unless the person's own words do.
    static let exampleWords = ["bramblewick", "odile", "fenn", "sourdough", "croissants", "rota"]

    static func system(_ form: QuillForm, today: String) -> String {
        rules(today: today) + "\n\n" + shape(form) + "\n\n" + example
    }

    static let reviseRules = """
        You are given a document as JSON and what is wrong with it. Return the whole document again as JSON that fits the \
        schema, changed only as the findings ask: keep every other word. If a finding says a fact was not given, replace \
        it with a bracketed placeholder.
        """

    // MARK: - Asks

    static func draft(form: QuillForm, brief: String?, ask: String?, sources: String, pages: Int?, paper: QuillPaper?) -> String {
        var parts = ["Write a \(form.rawValue)."]
        if let brief { parts.append("The brief: \(brief)") }
        if let ask, ask != brief { parts.append("What the person said: \(ask)") }
        if let pages { parts.append("It must fit on \(pages) page\(pages == 1 ? "" : "s").") }
        if let paper { parts.append("Paper: \(paper.rawValue).") }
        if !sources.isEmpty { parts.append("Sources:\n\(sources)") }
        return parts.joined(separator: "\n\n")
    }

    static func outline(form: QuillForm, brief: String?, ask: String?, sources: String, pages: Int?) -> String {
        draft(form: form, brief: brief, ask: ask, sources: sources, pages: pages, paper: nil)
            + "\n\nFirst, only its outline: the title, subtitle, author, date, who it is for, and its sections (at most eight), each with a heading and the points it will make."
    }

    static func section(_ index: Int, of outline: QuillOutline, brief: String?, sources: String) -> String {
        let section = outline.sections[index]
        let plan = outline.sections.enumerated().map { "\($0.offset + 1). \($0.element.heading)" }.joined(separator: "\n")
        var parts = ["Write section \(index + 1) of the \(outline.form.rawValue) \"\(outline.title)\": \"\(section.heading)\"."]
        parts.append("Its points: " + section.points.joined(separator: "; "))
        parts.append("The whole outline:\n\(plan)")
        if let brief { parts.append("The brief: \(brief)") }
        if !sources.isEmpty { parts.append("Sources:\n\(sources)") }
        parts.append("Return only this section's blocks, without its heading (level 2 headings inside it are fine).")
        return parts.joined(separator: "\n\n")
    }

    static func revise(_ document: QuillDocument, findings: [QuillFinding], change: String?) throws -> String {
        var parts: [String] = []
        if let change { parts.append("Change it as the person asks: \(change)") }
        if !findings.isEmpty {
            parts.append("What to fix:\n" + findings.prefix(16).map { "- \($0.sentence)" }.joined(separator: "\n"))
        }
        parts.append("The document:\n" + String(decoding: try JSONEncoder().encode(document), as: UTF8.self))
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Schemas

    static var documentSchema: Data { json(document(form: true)) }
    static var blocksSchema: Data { json(["type": "object", "properties": ["blocks": ["type": "array", "items": block]], "required": ["blocks"]]) }
    static var outlineSchema: Data {
        json(["type": "object", "properties": [
            "title": ["type": "string"], "subtitle": ["type": "string"], "author": ["type": "string"], "date": ["type": "string"],
            "to": ["type": "array", "items": ["type": "string"]],
            "sections": ["type": "array", "maxItems": 8, "items": ["type": "object", "properties": [
                "heading": ["type": "string"], "points": ["type": "array", "items": ["type": "string"]]], "required": ["heading", "points"]]],
        ], "required": ["title", "sections"]])
    }

    static var block: [String: Any] { ["type": "object", "properties": [
        "kind": ["type": "string", "enum": QuillBlock.Kind.allCases.map(\.rawValue)],
        "text": ["type": "string"], "level": ["type": "integer"], "title": ["type": "string"], "by": ["type": "string"],
        "path": ["type": "string"], "items": ["type": "array", "items": ["type": "string"]], "ordered": ["type": "boolean"],
        "rows": ["type": "array", "items": ["type": "array", "items": ["type": "string"]]],
        "fields": ["type": "array", "items": ["type": "object", "properties": ["label": ["type": "string"], "value": ["type": "string"]], "required": ["label"]]],
    ], "required": ["kind"]] }

    static func document(form: Bool) -> [String: Any] {
        var properties: [String: Any] = [
            "title": ["type": "string"], "subtitle": ["type": "string"], "author": ["type": "string"], "date": ["type": "string"],
            "from": ["type": "array", "items": ["type": "string"]], "to": ["type": "array", "items": ["type": "string"]],
            "style": ["type": "object", "properties": [
                "face": ["type": "string", "enum": QuillFace.allCases.map(\.rawValue)],
                "accent": ["type": "string", "enum": QuillStyle.accents.keys.sorted()],
                "numbered": ["type": "boolean"], "contents": ["type": "boolean"]]],
            "blocks": ["type": "array", "items": block],
        ]
        if form { properties["form"] = ["type": "string", "enum": QuillForm.allCases.map(\.rawValue)] }
        return ["type": "object", "properties": properties, "required": ["title", "blocks"]]
    }

    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

/// A long document's plan: its first page and its sections, each with the points it makes.
struct QuillOutline: Decodable, Equatable {
    struct Section: Decodable, Equatable {
        var heading: String
        var points: [String]

        private enum Key: String, CodingKey { case heading, points }
        init(heading: String, points: [String]) { self.heading = heading; self.points = points }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            heading = QuillLoose.text(c, .heading) ?? ""
            points = QuillLoose.lines(c, .points)
        }
    }

    var form: QuillForm = .report
    var title: String
    var subtitle: String?
    var author: String?
    var date: String?
    var to: [String]
    var sections: [Section]

    private enum Key: String, CodingKey { case title, subtitle, author, date, to, sections }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        title = QuillLoose.text(c, .title) ?? ""
        subtitle = QuillLoose.text(c, .subtitle)
        author = QuillLoose.text(c, .author)
        date = QuillLoose.text(c, .date)
        to = QuillLoose.lines(c, .to)
        sections = Array(QuillLoose.list(c, .sections, of: Section.self).filter { !$0.heading.isEmpty }.prefix(8))
    }
}

/// One section's blocks.
struct QuillSectionBlocks: Decodable {
    var blocks: [QuillBlock]
    private enum Key: String, CodingKey { case blocks }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        blocks = QuillLoose.list(c, .blocks, of: QuillBlock.self)
    }
}
