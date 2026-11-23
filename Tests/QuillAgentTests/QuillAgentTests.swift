import Foundation
import GraniteAgents
import XCTest
@testable import QuillAgent

/// The package as an app finds it: the record, what a model is shown, and what is refused before anything is written.
final class QuillAgentTests: XCTestCase {
    func testTheRecordIsFoundWithNothingListed() throws {
        let quill = try XCTUnwrap(GraniteRoster.discovered().package("quill"), "the record is in this test binary")
        XCTAssertEqual(quill.module, "QuillAgent")
        XCTAssertEqual(quill.summary, QuillAgent.summary)
    }

    func testTheSchemaIsWhatAModelIsShown() {
        let quill = AnyAgentPackage(QuillAgent.self)
        XCTAssertEqual(quill.schema, .object([
            .init(name: "brief", schema: .string, required: false),
            .init(name: "form", schema: .choice(["letter", "memo", "report", "resume", "proposal", "contract", "worksheet", "onepager"]), required: false),
            .init(name: "formats", schema: .array(.choice(["pdf", "docx", "pages", "html", "md"])), required: false),
            .init(name: "sources", schema: .array(.string), required: false),
            .init(name: "spec", schema: .string, required: false),
            .init(name: "output", schema: .string, required: false),
            .init(name: "pages", schema: .integer, required: false),
            .init(name: "paper", schema: .choice(["letter", "a4"]), required: false),
            .init(name: "rounds", schema: .integer, required: false),
            .init(name: "directory", schema: .string, required: false),
        ]))
        XCTAssertTrue(quill.takesDirectory)
        XCTAssertEqual(Set(quill.fields.keys), ["brief", "form", "formats", "sources", "spec", "output", "pages", "paper", "rounds"],
                       "a note beside every field the model sees")
        XCTAssertEqual(quill.lanes, 1)
        XCTAssertTrue(quill.needs.isEmpty)
        XCTAssertNil(quill.keeps)
        XCTAssertEqual(QuillAgent.makes.map(\.kind), ["document"])
        XCTAssertEqual(QuillAgent.makes.first?.into, ["quill/*"])
    }

    func testTheGuideSaysHowToCallAndNeverToWriteTheFilesByHand() {
        let guide = AnyAgentPackage(QuillAgent.self).guide
        for words in ["never write the document's HTML, CSS, Markdown or .docx by hand", "\"form\": \"letter\", \"formats\": [\"docx\"]",
                      "and nothing they did not", "bracketed place to fill in", "\"pages\": 1", "{\"sources\": [\"notes/q3.md\"]",
                      "\"spec\": \"quill/cover-letter/cover-letter.quill.json\"", "The PDF is always written and shown"] {
            XCTAssertTrue(guide.contains(words), "the guide says \(words)")
        }
    }

    /// Refused through the roster as a host calls it, each with its kind, and nothing written.
    func testARefusalComesBeforeAnyWorkAndWritesNothing() async throws {
        let folder = try Fixture.folder()
        try Data([0, 1, 2, 0]).write(to: folder.appendingPathComponent("blob.bin"))
        try Fixture.write("{\"title\": \"not a draft\"}", to: "old.quill.json", in: folder)
        let rows: [(input: [String: Any], kind: AgentRefusal.Kind, says: String)] = [
            ([:], .call, "nothing to write from"),
            (["brief": "   "], .call, "nothing to write from"),
            (["sources": ["missing.md"]], .call, "no file at missing.md"),
            (["sources": ["blob.bin"]], .input, "blob.bin has no text quill reads"),
            (["spec": "old.quill.json"], .input, "is not a draft quill wrote"),
            (["brief": "a letter", "pages": 0], .call, "`pages` is 0"),
            (["brief": "a letter to the council"], .model, "quill"),
        ]
        for row in rows {
            do {
                _ = try await Fixture.perform(row.input, in: folder)
                XCTFail("refused: \(row.input)")
            } catch {
                let refusal = try XCTUnwrap(AgentRefusal.of(error), "\(row.input): \(error)")
                XCTAssertEqual(refusal.kind, row.kind, "\(row.input): \(refusal)")
                XCTAssertTrue(refusal.description.contains(row.says), "\(row.input): \(refusal)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("quill").path), "a refusal writes nothing")
    }

    func testAFormIsReadLooselyAndGuessedFromABrief() {
        XCTAssertEqual(QuillForm(loose: "Cover Letter"), .letter)
        XCTAssertEqual(QuillForm(loose: "CV"), .resume)
        XCTAssertEqual(QuillForm(loose: "NDA"), .contract)
        XCTAssertNil(QuillForm(loose: "spaceship"))
        XCTAssertEqual(QuillForm.guessed(from: "write me a cover letter for the analyst job"), .letter)
        XCTAssertEqual(QuillForm.guessed(from: "a one-page flyer for the bake sale"), .onepager)
        XCTAssertEqual(QuillForm.guessed(from: "the quarterly numbers for the board"), .report)
        XCTAssertEqual(QuillFormat.chosen(nil), [.pdf, .docx], "a PDF and a Word file when none are named")
        XCTAssertEqual(QuillFormat.chosen([.md, .pages, .md]), [.pdf, .pages, .md], "the PDF always, each once")
    }
}
