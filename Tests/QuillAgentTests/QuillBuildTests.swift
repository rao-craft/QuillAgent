import Foundation
import GraniteAgents
import PDFKit
import XCTest
@testable import QuillAgent

/// The package installed as Granite's `AgentInstaller` installs it (a runner of one executable, built in release) and
/// asked over the wire in a process of its own, with no model: WebKit lays the pages out in the runner, with no window.
/// Gated (`QUILL_BUILD=1`): the build takes a minute or two.
final class QuillBuildTests: XCTestCase {
    func testTheInstalledRunnerWritesADocumentOverTheWire() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QUILL_BUILD"] == "1", "set QUILL_BUILD=1 to install and run the agent")
        let shelf = try Fixture.folder()
        // A copy, as Craft installs from a clone: `swift test` holds this package's own folder.
        let source = try Fixture.folder().appendingPathComponent("QuillAgent")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for item in ["Package.swift", "Package.resolved", "Sources", "Tests"]
        where FileManager.default.fileExists(atPath: Fixture.package.appendingPathComponent(item).path) {
            try FileManager.default.copyItem(at: Fixture.package.appendingPathComponent(item), to: source.appendingPathComponent(item))
        }
        let installation = try await AgentInstaller(folder: shelf).install(.path(source.path))
        XCTAssertEqual(installation.name, "QuillAgent")

        let executable = AgentShelf(folder: shelf).executable(of: installation)
        let entries = try await AgentProcess(executable: executable).describe()
        XCTAssertEqual(entries.map(\.word), ["quill"])
        XCTAssertEqual(entries.first?.makes?.map(\.kind), ["document"], "what it makes crosses --describe")

        let project = try Fixture.folder()
        try Fixture.write(Fixture.report, to: "notes/renovation.md", in: project)
        // No model: a brief is the model's refusal, over the wire.
        do {
            _ = try await AgentProcess(executable: executable)
                .perform(word: "quill", input: JSONSerialization.data(withJSONObject: ["brief": "a letter to the council"]), host: AgentHost(directory: project.path))
            XCTFail("no model")
        } catch AgentRemoteError.refused(_, let refusal, _) {
            XCTAssertEqual(refusal.kind, .model, "\(refusal)")
        }
        // A Markdown source laid out as written: the PDF and the Word file, from the runner's own WebKit.
        let answer = try await AgentProcess(executable: executable)
            .perform(word: "quill", input: JSONSerialization.data(withJSONObject: ["sources": ["notes/renovation.md"]]), host: AgentHost(directory: project.path))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: answer) as? [String: Any])
        XCTAssertEqual(object["format"] as? String, "granite-answer/1")
        let paths = try XCTUnwrap(object["paths"] as? [String])
        XCTAssertEqual(paths.map { URL(fileURLWithPath: $0).pathExtension }, ["pdf", "docx", "json"])
        let pdf = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: paths[0])))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 3)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Harbor Library Renovation") == true)
        Fixture.keep(paths, as: "runner")
    }
}
