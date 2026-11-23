import Foundation
import GraniteAgents

/// What a call answers: the document's files (the PDF first), what it is, and what is left for the person to do.
/// Paths are absolute.
///
/// PIN: EVERY KEY OF THE STANDARD IS STORED. `made`, `expected`, `problems` and `interactions` are properties here, not
/// the protocol's empty defaults, so they are encoded into the answer a host reads.
/// PIN: THE PDF LEADS. `path` and the preview's first file are the PDF, which any host can show; Word and Pages files are
/// beside it.
public struct QuillResult: AgentAnswer, Equatable {
    /// The PDF.
    public var path: String
    public var paths: [String]
    /// The draft kept beside the files, to write again or change later (`spec`).
    public var spec: String
    public var title: String
    public var form: QuillForm
    public var formats: [QuillFormat]
    public var pages: Int
    public var words: Int
    /// Model rounds: 0 for a document laid out as written.
    public var rounds: Int
    /// Steps tighter than the form's own measures the kit set the pages to fit.
    public var tightened: Int
    /// What the pages or the draft still do not do, one sentence each.
    public var findings: [String]
    /// Bracketed places left for the person to fill in, as written in the document.
    public var placeholders: [String]
    public var notes: [String]
    public var made: [AgentMade]
    public var expected: [AgentExpected]
    public var problems: [AgentProblem]
    public var interactions: [AgentInteraction]
}
