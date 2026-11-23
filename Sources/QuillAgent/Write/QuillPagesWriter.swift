import Foundation
import GraniteAgents

/// The Word file saved as a Pages file. Written in Phase 4.
enum QuillPagesWriter {
    static func write(docx: URL, to pages: URL) -> Result<AgentMade.State, Failure> {
        .failure(Failure("Pages files are not written yet: open the Word file in Pages"))
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
