import Foundation
import GraniteAgents

/// What a call is refused for before anything is written, each with its fix.
public enum QuillError: Error, Equatable, CustomStringConvertible {
    /// No brief, no sources, no spec: nothing to write from.
    case nothing
    /// A source that is not there.
    case noSource(String)
    /// A source with no text this agent reads.
    case unreadableSource(String)
    /// A spec that is not there, or is not a draft this agent wrote.
    case badSpec(String)
    /// A page limit under one.
    case badPages(Int)
    /// WebKit could not lay out or export the pages.
    case render(String)
    /// The files could not be written.
    case unwritable(String)

    public var description: String {
        switch self {
        case .nothing:
            return "nothing to write from: give `brief` with what the document says, `sources` with the files it is drawn from, or `spec` with a draft written before"
        case .noSource(let path):
            return "no file at \(path): give `sources` as paths relative to the project"
        case .unreadableSource(let path):
            return "\(path) has no text quill reads: give Markdown, text, Word, RTF, HTML or PDF"
        case .badSpec(let path):
            return "\(path) is not a draft quill wrote (a .quill.json beside its document): give the .quill.json path, or leave `spec` out"
        case .badPages(let pages):
            return "`pages` is \(pages): give a page limit of one or more, or leave it out"
        case .render(let reason):
            return "the pages could not be laid out: \(reason)"
        case .unwritable(let reason):
            return "the document could not be written: \(reason)"
        }
    }
}

/// The refusals as the answer standard counts them: what the call can change is the call's; a source or spec that is
/// there but unreadable is the input's; WebKit or the disk failing is the host's.
extension QuillError: AgentRefusing {
    public var refusal: AgentRefusal {
        switch self {
        case .nothing, .noSource, .badPages: return AgentRefusal(.call, description)
        case .unreadableSource, .badSpec: return AgentRefusal(.input, description)
        case .render, .unwritable: return AgentRefusal(.host, description)
        }
    }
}
