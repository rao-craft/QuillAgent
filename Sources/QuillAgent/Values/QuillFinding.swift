import Foundation

/// Something the draft or its pages do not yet do, in one sentence a model can act on. The kit fixes what is its own
/// (a line left alone, a heading at a page's foot, a page over by a few lines); the rest goes back to the model, and what
/// is left after the last round goes into the answer's problems.
public struct QuillFinding: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// More pages than asked.
        case pages
        /// A table or code block wider than the column.
        case wide
        /// A block taller than a page.
        case tall
        /// A paragraph that still leaves one line alone on a page.
        case alone
        /// A field over its limit, or empty where the form needs it.
        case limit
        /// A name, date or figure the ask and the sources do not give.
        case invented
        /// A contact line, author, signature or speaker the brief does not give, replaced by a bracketed place.
        case replaced
        /// Words copied from the prompt's example.
        case echo
        /// A figure whose picture is not there.
        case picture
    }

    public var kind: Kind
    /// The block it is about, when it is one.
    public var block: Int?
    public var sentence: String

    public init(_ kind: Kind, block: Int? = nil, _ sentence: String) {
        self.kind = kind; self.block = block; self.sentence = sentence
    }

    /// Findings the model can fix by rewriting its words; the others are the kit's or the person's.
    var isTheModels: Bool { [.pages, .wide, .tall, .limit, .invented, .echo].contains(kind) }
}
