//  WHAT: A document written from an ask, as a Granite agent package. The host's model drafts it as blocks (headings,
//        paragraphs, lists, tables, quotes, callouts, figures, fields, signature lines); the kit composes them into
//        pages in the form's house style; WebKit lays the pages out and measures them; the kit fixes what is its own and
//        the model rewrites what is its own; then the one draft is written as PDF, Word, Pages, HTML and Markdown.
//  IN:   Input: the brief, the form, the formats, the sources, a page limit, or a draft written before (`spec`).
//  OUT:  QuillResult: the files (the PDF first, previewed), the draft kept beside them, the pages, what is left to fill in.
//  PIN:  THE MODEL OWNS THE WORDS, THE KIT OWNS THE PAGE. A draft is blocks, never HTML or sizes, so every format is
//        written from the same thing and a local model never has to get CSS right.
//  PIN:  NOTHING INVENTED. A name, a date, a figure or a quote's speaker stays only when the ask or the sources give it;
//        anything else is a bracketed place the answer lists for the person to fill in.
//  PIN:  ONE WEBKIT PAGE. `lanes` is one: every call lays its pages out on the same WebPage, one after another.

import Foundation
import GraniteAgents

public struct QuillAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable {
        /// What the document says, in the person's words.
        public var brief: String?
        public var form: QuillForm?
        /// The files to write besides the PDF, which is always written.
        public var formats: [QuillFormat]?
        /// Files the document is drawn from, relative to the project.
        public var sources: [String]?
        /// A `.quill.json` written before, to write again or change.
        public var spec: String?
        /// Where to write: a folder, or a file whose name and type are used.
        public var output: String?
        /// The most pages it may take.
        public var pages: Int?
        public var paper: QuillPaper?
        /// Rounds of fixing what the pages measured.
        public var rounds: Int?
        /// The host's folder.
        public var directory: String?

        public init(brief: String? = nil, form: QuillForm? = nil, formats: [QuillFormat]? = nil, sources: [String]? = nil, spec: String? = nil,
                    output: String? = nil, pages: Int? = nil, paper: QuillPaper? = nil, rounds: Int? = nil, directory: String? = nil) {
            self.brief = brief; self.form = form; self.formats = formats; self.sources = sources; self.spec = spec
            self.output = output; self.pages = pages; self.paper = paper; self.rounds = rounds; self.directory = directory
        }
    }

    public typealias Event = QuillFrame
    public typealias Output = QuillResult
    public typealias Compute = QuillCompute

    public static let word = "quill"
    public static let summary = "writes a document (a letter, memo, report, resume, proposal, contract, worksheet or one-pager) laid out in pages and written as PDF, Word, Pages, HTML or Markdown from one draft."

    public static let fields = [
        "brief": "what the document says, in the person's words: who it is from and to, what it must cover, any names, dates and figures they gave; never invent any",
        "form": "letter, memo, report, resume, proposal, contract, worksheet or onepager; left out, chosen from the brief",
        "formats": "the files to write besides the PDF (always written): docx for Word, pages for Pages, html, md; left out, docx",
        "sources": "files the document is drawn from, relative to the project (Markdown, text, Word, RTF, HTML, PDF, or a folder of them); one Markdown file with no brief is laid out as written",
        "spec": "a .quill.json written beside an earlier document, to write it again; with a brief, changed as the brief asks",
        "output": "a folder, or a file such as Letters/cover-letter.docx whose name and type are used; left out, quill/<title>/",
        "pages": "the most pages it may take, when the person gave a limit (\"one page\" is 1)",
        "paper": "letter or a4; left out, letter",
        "rounds": "how many times to fix what the pages measured; 3 when left out",
    ]

    public static let guide = """
        Tag quill when the person asks for a document to keep, send, print or sign: a letter or cover letter, a memo, a \
        report, a resume, a proposal or quote, a contract or agreement, a worksheet or form, a one-pager or flyer, as \
        Word, Pages, PDF, HTML or Markdown. quill writes the words, lays them out in pages and writes every file itself: \
        never write the document's HTML, CSS, Markdown or .docx by hand, and never convert its files afterwards. \
        `{"brief": "a cover letter from Dana Reyes to Northwind for the data analyst role; she led the 2025 sales dashboard rebuild", "form": "letter", "formats": ["docx"]}` \
        writes the letter as a PDF and a Word file. Put in the brief every name, date, figure and fact the person gave, \
        and nothing they did not: what is missing is left as a bracketed place to fill in, which the answer lists. \
        `{"brief": "...", "formats": ["pages"], "pages": 1}` holds it to one page as a Pages file. \
        `{"sources": ["notes/q3.md"], "form": "report"}` lays a Markdown file out as written; add a brief to have it \
        rewritten. `{"spec": "quill/cover-letter/cover-letter.quill.json", "brief": "make it shorter and warmer"}` \
        changes a document written before. The PDF is always written and shown; tell the person where the files are \
        and what is left to fill in. A long document takes a few minutes.
        """

    /// One call at a time: one WebKit page lays every document out.
    public static let lanes: Int? = 1

    public static let makes = [
        AgentMake(kind: "document", what: "a document written from the ask: its PDF, and its Word, Pages, HTML or Markdown file",
                  into: ["quill/*"], never: "the project's code or its own Markdown, unless named as `output`"),
    ]

    public static func compute() async throws -> QuillCompute { await MainActor.run { QuillCompute() } }

    public static func output(from events: [QuillFrame]) -> QuillResult? { events.compactMap(\.result).last }

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<QuillFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await QuillLoop(input: input, host: context.host, compute: context.compute,
                                                     yield: { continuation.yield($0) }).run()
                    continuation.yield(.written(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
