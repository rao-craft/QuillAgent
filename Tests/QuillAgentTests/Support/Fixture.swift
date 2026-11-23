import Foundation
import GraniteAgents
import PDFKit
@testable import QuillAgent

enum Fixture {
    /// The package's own folder.
    static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quill-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    /// A report as a person writes one in Markdown: front matter, sections, a list, a table long enough to cross a page,
    /// a quote with its speaker, a callout, a page break. Every word is made up here.
    static let report = """
    ---
    author: Ines Calder
    date: November 2026
    ---
    # Harbor Library Renovation

    *A plan for the reading room and the archive*

    ## Why now

    The reading room has not changed since 1987. Its lights hum, its chairs wobble, and its one outlet strip powers \
    eleven laptops on a busy afternoon. Visits rose **18 percent** this year while the room stayed the same size.

    \(paragraphs(9))

    ## What we will do

    - Replace the lighting with warm, dimmable fixtures.
    - Add power at every table.
    - Move the archive to climate-controlled shelving.

    > The archive is the town's memory, and right now it lives in a damp basement.
    >
    > — Ines Calder

    > [!NOTE] The library stays open during the work, one wing at a time.

    ## Costs

    | Item | Cost | Weeks |
    |---|---|---|
    \((1...36).map { "| Item \($0) | $\($0 * 1250) | \($0 % 6 + 1) |" }.joined(separator: "\n"))

    <!-- pagebreak -->

    ## Appendix

    \(paragraphs(3))
    """

    static func paragraphs(_ count: Int) -> String {
        (1...count).map { "Paragraph \($0). The committee walked the room on a wet Tuesday and counted what worked and what did not, from the radiators under the windows to the reference desk by the door, and agreed the work should start with the light." }
            .joined(separator: "\n\n")
    }

    static func write(_ text: String, to name: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A call as a host makes it, through the roster: the answer's JSON.
    static func perform(_ input: [String: Any], in folder: URL, model: (any AgentHostModel)? = nil, notes: NoteBox? = nil) async throws -> [String: Any] {
        let host = AgentHost(directory: folder.path, model: model, note: { notes?.append($0) })
        let data = try await AnyAgentPackage(QuillAgent.self).perform(try JSONSerialization.data(withJSONObject: input), host: host)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    static func pdf(_ path: String) -> PDFDocument? { PDFDocument(url: URL(fileURLWithPath: path)) }

    /// With `QUILL_KEEP=<dir>`, a test's files are copied there under `name`, to open by hand.
    static func keep(_ files: [String], as name: String) {
        guard let dir = ProcessInfo.processInfo.environment["QUILL_KEEP"], !dir.isEmpty else { return }
        let target = URL(fileURLWithPath: dir).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for file in files {
            let url = URL(fileURLWithPath: file)
            let copy = target.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: url, to: copy)
        }
    }
}

