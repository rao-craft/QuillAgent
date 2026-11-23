import Foundation
import GraniteAgents
import PDFKit
import XCTest
@testable import QuillAgent

/// The model's part, with a scripted model: a draft, its grounding, the checks and the pages, and the rounds that fix
/// what the model can fix. Every name is made up here.
@MainActor
final class QuillDraftingTests: XCTestCase {
    static let brief = "a cover letter from Dana Reyes to Northwind for the data analyst role; she rebuilt the 2025 sales dashboard"

    static func letter(_ paragraphs: [String], from: [String] = ["Dana Reyes"], signature: String = "Dana Reyes") -> String {
        let blocks = paragraphs.map { "{\"kind\": \"paragraph\", \"text\": \(Self.quoted($0))}" }
            + ["{\"kind\": \"signature\", \"text\": \(Self.quoted(signature))}"]
        let fromJSON = "[" + from.map(Self.quoted).joined(separator: ", ") + "]"
        return """
        {"form": "letter", "title": "", "from": \(fromJSON), "to": ["[Hiring Manager's Name]", "Northwind"], "date": "\(QuillDrafting.today)",
         "blocks": [\(blocks.joined(separator: ","))]}
        """
    }

    static func quoted(_ text: String) -> String { String(decoding: try! JSONEncoder().encode(text), as: UTF8.self) }

    static let opening = ["Dear [Hiring Manager's Name],",
                          "I am writing to apply for the data analyst role at Northwind. Last year I rebuilt our 2025 sales dashboard from the ground up.",
                          "I would welcome the chance to talk.", "Sincerely,"]

    func testACleanLetterIsOneAskAndListsWhatIsLeftToFillIn() async throws {
        let folder = try Fixture.folder()
        let model = FakeHostModel(json: [Self.letter(Self.opening)])
        let notes = NoteBox()
        let answer = try await Fixture.perform(["brief": Self.brief, "formats": ["docx"]], in: folder, model: model, notes: notes)

        XCTAssertEqual(model.asked.count, 1, "a clean draft needs no revise")
        let ask = try XCTUnwrap(model.asked.first)
        XCTAssertTrue(ask.system.contains("Never invent a person"), "the house rules")
        XCTAssertTrue(ask.system.contains("A letter: `from` is the sender's lines"), "the letter's shape, the form guessed from the brief")
        XCTAssertTrue(ask.user.contains("The brief: \(Self.brief)"))
        XCTAssertEqual(answer["form"] as? String, "letter")
        XCTAssertEqual(answer["rounds"] as? Int, 1)
        XCTAssertEqual(answer["placeholders"] as? [String], ["[Hiring Manager's Name]"])
        let problems = try XCTUnwrap(answer["problems"] as? [[String: Any]])
        XCTAssertEqual(problems.compactMap { $0["kind"] as? String }, ["placeholder"], "\(problems)")
        XCTAssertTrue(notes.lines.contains("drafting a letter"), "\(notes.lines)")
        XCTAssertTrue(notes.lines.contains { $0.hasPrefix("round 1: measured clean, 1 page") }, "\(notes.lines) \(answer["problems"] ?? "")")

        let pdf = try XCTUnwrap(Fixture.pdf(try XCTUnwrap(answer["path"] as? String)))
        XCTAssertEqual(pdf.pageCount, 1)
        // Lines wrap: words are matched with their spaces joined.
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: " ").split { $0.isWhitespace }.joined(separator: " ")
        XCTAssertTrue(text.contains("Dear [Hiring Manager's Name],") && text.contains("2025 sales dashboard") && text.contains("Dana Reyes"), text)
        let paths = try XCTUnwrap(answer["paths"] as? [String])
        Fixture.keep(paths, as: "letter")
        XCTAssertEqual(paths.map { URL(fileURLWithPath: $0).pathExtension }, ["pdf", "docx", "json"])
    }

    func testALetterOverItsPageLimitIsRevisedToFit() async throws {
        let folder = try Fixture.folder()
        let long = Self.opening + Array(repeating: "I also led the weekly reporting work for the regional sales team, and I enjoyed every part of it, from the first request to the final review with the managers.", count: 30)
        let model = FakeHostModel(json: [Self.letter(long), Self.letter(Self.opening)])
        let answer = try await Fixture.perform(["brief": Self.brief, "pages": 1, "formats": ["md"]], in: folder, model: model)

        XCTAssertEqual(model.asked.count, 2)
        let revise = try XCTUnwrap(model.asked.last)
        XCTAssertTrue(revise.user.contains("must be 1: cut about"), revise.user.prefix(300).description)
        XCTAssertTrue(revise.system.contains("changed only as the findings ask"))
        XCTAssertTrue(revise.user.contains("\"kind\":\"paragraph\""), "the draft itself, as JSON")
        XCTAssertEqual(answer["rounds"] as? Int, 2)
        XCTAssertEqual(answer["pages"] as? Int, 1)
    }

    func testWhatTheBriefDoesNotGiveIsAPlaceOrGoesBackToTheModel() async throws {
        let folder = try Fixture.folder()
        let invented = Self.opening.map { $0 == "I would welcome the chance to talk." ? "My dashboard cut reporting time by 37% across 14 offices." : $0 }
        let model = FakeHostModel(json: [
            Self.letter(invented, from: ["Dana Reyes", "99 Larkspur Road", "dana@example.com"], signature: "Dana Q. Reyes"),
            Self.letter(Self.opening, from: ["Dana Reyes", "99 Larkspur Road", "dana@example.com"], signature: "Dana Q. Reyes"),
        ])
        let answer = try await Fixture.perform(["brief": Self.brief, "formats": ["md"]], in: folder, model: model)

        XCTAssertEqual(model.asked.count, 2, "the invented figures go back to the model")
        let revise = try XCTUnwrap(model.asked.last?.user)
        XCTAssertTrue(revise.contains("gives 14, 37%, which the brief and sources do not"), revise.prefix(400).description)
        XCTAssertFalse(revise.contains("99 Larkspur Road"), "the model revises the grounded draft: the kit's places are not its to undo")
        let spec = try JSONDecoder().decode(QuillDocument.self, from: Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(answer["spec"] as? String))))
        XCTAssertEqual(spec.from, ["Dana Reyes", "[Your Address]", "[Email]"], "an address and email no one gave are places")
        XCTAssertEqual(spec.blocks.last?.text, "[Your Name]", "a middle initial no one gave is not the person's name")
        let placeholders = try XCTUnwrap(answer["placeholders"] as? [String])
        XCTAssertTrue(placeholders.contains("[Your Address]") && placeholders.contains("[Email]"), "\(placeholders)")
        let problems = (answer["problems"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
        XCTAssertTrue(problems.contains { $0.contains("\"99 Larkspur Road\" is not in the brief: written as [Your Address]") }, "\(problems)")
    }

    func testACopiedExampleIsCaughtAndRewritten() async throws {
        let folder = try Fixture.folder()
        let copied = Self.opening.map { $0.hasPrefix("I would") ? "I bake sourdough for the Bramblewick rota." : $0 }
        let model = FakeHostModel(json: [Self.letter(copied), Self.letter(Self.opening)])
        let answer = try await Fixture.perform(["brief": Self.brief, "formats": ["md"]], in: folder, model: model)
        XCTAssertEqual(model.asked.count, 2)
        XCTAssertTrue(model.asked[1].user.contains("it copies the example's words (bramblewick, sourdough, rota)"), model.asked[1].user.prefix(300).description)
        XCTAssertEqual(answer["rounds"] as? Int, 2)
    }

    func testAReportIsOutlinedThenWrittenASectionAtATime() async throws {
        let folder = try Fixture.folder()
        try Fixture.write("Visits rose 18 percent in 2025. The roof leaks over the archive.", to: "notes.txt", in: folder)
        let outline = """
        {"title": "Harbor Library", "subtitle": "The case for renovation", "author": "Ines Calder", "date": "[Date]",
         "sections": [{"heading": "Why now", "points": ["visits rose 18 percent"]}, {"heading": "The archive", "points": ["the roof leaks"]},
                      {"heading": "Next steps", "points": ["a vote"]}]}
        """
        let section = { (text: String) in "{\"blocks\": [{\"kind\": \"heading\", \"text\": \"Repeated\", \"level\": 1}, {\"kind\": \"paragraph\", \"text\": \"\(text)\"}]}" }
        let model = FakeHostModel(json: [outline, section("Visits rose 18 percent in 2025."), section("The roof leaks over the archive."), "not json"])
        let notes = NoteBox()
        let answer = try await Fixture.perform(["brief": "a report for the trustees on renovating Harbor Library, by Ines Calder", "sources": ["notes.txt"], "formats": ["md"]],
                                               in: folder, model: model, notes: notes)

        XCTAssertEqual(model.asked.count, 4, "the outline, then one ask per section")
        XCTAssertTrue(model.asked[0].user.contains("only its outline"))
        XCTAssertTrue(model.asked[1].user.contains("Write section 1 of the report \"Harbor Library\": \"Why now\""))
        XCTAssertTrue(model.asked[1].user.contains("=== notes.txt ==="), "the sources ride every section")
        XCTAssertTrue(notes.lines.contains("outlining a report"))
        XCTAssertTrue(notes.lines.contains { $0.hasPrefix("section 3 was not written") }, "a section the model fails keeps its points: \(notes.lines)")
        let spec = try JSONDecoder().decode(QuillDocument.self, from: Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(answer["spec"] as? String))))
        XCTAssertEqual(spec.blocks.filter { $0.kind == .heading }.compactMap(\.text), ["Why now", "The archive", "Next steps"], "a repeated top heading is dropped")
        XCTAssertEqual(spec.blocks.last?.items, ["a vote"])
        XCTAssertEqual(spec.author, "Ines Calder")
        XCTAssertEqual(answer["form"] as? String, "report")
    }

    func testADraftWrittenBeforeIsChangedAsAsked() async throws {
        let folder = try Fixture.folder()
        let first = FakeHostModel(json: [Self.letter(Self.opening)])
        let answer = try await Fixture.perform(["brief": Self.brief, "formats": ["md"]], in: folder, model: first)
        let spec = try XCTUnwrap(answer["spec"] as? String)
        let relative = String(spec.dropFirst(folder.path.count + 1))

        let warmer = Self.opening.map { $0 == "I would welcome the chance to talk." ? "I would love the chance to talk." : $0 }
        let second = FakeHostModel(json: [Self.letter(warmer)])
        let changed = try await Fixture.perform(["spec": relative, "brief": "make it warmer"], in: folder, model: second)
        XCTAssertEqual(second.asked.count, 1)
        XCTAssertTrue(second.asked[0].user.contains("Change it as the person asks: make it warmer"))
        XCTAssertTrue(second.asked[0].user.contains("rebuilt our 2025 sales dashboard"), "the earlier draft is what is changed")
        XCTAssertEqual(changed["spec"] as? String, spec, "written again in the same place")
        let made = try XCTUnwrap(changed["made"] as? [[String: Any]])
        XCTAssertEqual(made.first?["state"] as? String, "rewritten")

        // Without a brief, a spec is written again with no model at all.
        let again = try await Fixture.perform(["spec": relative], in: folder)
        XCTAssertEqual(again["rounds"] as? Int, 0)
    }

    func testARevisionTheModelFailsKeepsTheBestRound() async throws {
        let folder = try Fixture.folder()
        let invented = Self.opening.map { $0 == "I would welcome the chance to talk." ? "I saved 37% on reporting." : $0 }
        let model = FakeHostModel(json: [Self.letter(invented), "{ not json"])
        let answer = try await Fixture.perform(["brief": Self.brief, "formats": ["md"]], in: folder, model: model)
        XCTAssertEqual(model.asked.count, 2)
        XCTAssertEqual(answer["rounds"] as? Int, 1, "the first round, kept")
        let problems = (answer["problems"] as? [[String: Any]] ?? []).compactMap { $0["kind"] as? String }
        XCTAssertTrue(problems.contains("invented"), "what was left is said: \(problems)")
    }

    func testAFirstDraftThatIsNotJSONIsTheModelsRefusal() async throws {
        let folder = try Fixture.folder()
        do {
            _ = try await Fixture.perform(["brief": Self.brief], in: folder, model: FakeHostModel(json: ["nope"]))
            XCTFail("refused")
        } catch {
            XCTAssertEqual(AgentRefusal.of(error)?.kind, .model, "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("quill").path))
    }
}
