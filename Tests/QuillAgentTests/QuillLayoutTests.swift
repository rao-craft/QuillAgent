import Foundation
import GraniteAgents
import PDFKit
import XCTest
@testable import QuillAgent

/// A document laid out in pages with no model: a Markdown file as written, through the roster as a host calls it, and
/// the kit's own fixes measured on the pages WebKit made.
@MainActor
final class QuillLayoutTests: XCTestCase {
    func testAMarkdownReportIsLaidOutInLetterPagesAndWrittenAsEveryFormatAsked() async throws {
        let folder = try Fixture.folder()
        try Fixture.write(Fixture.report, to: "notes/renovation.md", in: folder)
        let notes = NoteBox()
        let answer = try await Fixture.perform(["sources": ["notes/renovation.md"], "formats": ["html", "md"]], in: folder, notes: notes)

        XCTAssertEqual(answer["format"] as? String, "granite-answer/1", "stamped by the runner")
        let pdfPath = try XCTUnwrap(answer["path"] as? String)
        XCTAssertEqual(pdfPath, folder.appendingPathComponent("quill/harbor-library-renovation/harbor-library-renovation.pdf").path)
        let paths = try XCTUnwrap(answer["paths"] as? [String])
        XCTAssertEqual(paths.map { URL(fileURLWithPath: $0).lastPathComponent },
                       ["harbor-library-renovation.pdf", "harbor-library-renovation.html", "harbor-library-renovation.md",
                        "harbor-library-renovation.quill.json"])
        let made = try XCTUnwrap(answer["made"] as? [[String: Any]])
        XCTAssertEqual(made.compactMap { $0["name"] as? String }, ["harbor-library-renovation.pdf", "harbor-library-renovation.html", "harbor-library-renovation.md"])
        XCTAssertEqual((answer["expected"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual(answer["rounds"] as? Int, 0, "laid out as written: no model")
        let interactions = try XCTUnwrap(answer["interactions"] as? [[String: Any]])
        XCTAssertEqual(interactions.first?["kind"] as? String, "preview")
        XCTAssertEqual(interactions.first?["paths"] as? [String], [pdfPath], "the PDF leads")
        XCTAssertTrue(notes.lines.contains("laying out notes/renovation.md as written"), "\(notes.lines)")

        Fixture.keep(paths, as: "report")
        let pdf = try XCTUnwrap(Fixture.pdf(pdfPath))
        XCTAssertEqual(pdf.pageCount, answer["pages"] as? Int)
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 3)
        XCTAssertEqual(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Harbor Library Renovation")
        XCTAssertEqual(pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, "Ines Calder")
        for index in 0..<pdf.pageCount {
            let box = try XCTUnwrap(pdf.page(at: index)).bounds(for: .mediaBox)
            XCTAssertEqual(box.width, 612, accuracy: 0.5); XCTAssertEqual(box.height, 792, accuracy: 0.5)
        }
        let first = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertTrue(first.contains("Harbor Library Renovation"))
        XCTAssertTrue(first.contains("A plan for the reading room and the archive"), "the italic line under the title is its subtitle")
        XCTAssertTrue(first.contains("Ines Calder · November 2026"))
        let all = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        for words in ["18 percent", "Replace the lighting", "the town's memory", "— Ines Calder", "one wing at a time", "Item 36", "$45000"] {
            XCTAssertTrue(all.contains(words), "the PDF has \(words)")
        }
        let last = try XCTUnwrap(pdf.page(at: pdf.pageCount - 1)?.string)
        XCTAssertTrue(last.hasPrefix("Appendix") || last.contains("\nAppendix") || last.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Harbor Library Renovation\nAppendix") || last.contains("Appendix\n"),
                      "the page break puts the appendix on a page of its own: \(last.prefix(80))")
        XCTAssertTrue(all.contains("2 of \(pdf.pageCount)"), "page numbers run along the foot")

        // The HTML stands alone; the Markdown reads back to the same blocks.
        let html = try String(contentsOfFile: paths[1], encoding: .utf8)
        XCTAssertTrue(html.contains("<title>Harbor Library Renovation</title>") && !html.contains("column-width"), "the reading page, not the paged one")
        let markdown = try String(contentsOfFile: paths[2], encoding: .utf8)
        let spec = try JSONDecoder().decode(QuillDocument.self, from: Data(contentsOf: URL(fileURLWithPath: paths[3])))
        XCTAssertEqual(QuillMarkdownReader.read(markdown, form: .report, name: "x").blocks, spec.blocks, "Markdown out reads back in")
    }

    /// The kit's own fix: no paragraph leaves one line alone at a page's foot or head.
    func testNoParagraphLeavesOneLineAloneOnAPage() async throws {
        let renderer = QuillRenderer()
        // Paragraphs of different lengths, so some would split badly.
        let blocks = (1...40).map { index in
            QuillBlock.paragraph(String(repeating: "The council met again and the minutes were read aloud in full. ", count: index % 5 + 1))
        }
        let document = QuillDocument(form: .report, title: "Minutes", blocks: blocks)
        var layout = QuillLayout.of(document)
        let before = try await renderer.measure(QuillKit.page(document, layout: layout, mode: .paged), paper: .letter, layout: layout)
        let alone = try XCTUnwrap(before.alone.first, "the form's own measures leave a line alone (block 13's last line)")
        let settled = try await QuillPaging.settle(document, pictures: [:], layout: &layout, renderer: renderer)
        XCTAssertTrue(layout.pushed.contains(alone.q), "the paragraph is pushed whole to the next page")
        XCTAssertTrue(settled.alone.filter { !$0.top }.isEmpty, "every split leaves two lines or more: \(settled.alone)")
        // Through the whole loop, nothing is left alone either way.
        let paged = try await renderer.lay(document, pictures: [:], limit: nil)
        XCTAssertTrue(paged.raw.alone.filter { !$0.top }.isEmpty, "\(paged.raw.alone)")
        XCTAssertEqual(paged.pages.count, paged.raw.pages)
    }

    /// Over a limit, tighter within the floors; what will not fit is a finding with a count of words to cut.
    func testAPageLimitIsMetByTighteningOrSaidAsWordsToCut() async throws {
        let renderer = QuillRenderer()
        func letter(_ paragraphs: Int) -> QuillDocument {
            QuillDocument(form: .letter, title: "", date: "November 22, 2026", from: ["12 Pier Road", "Saltmere"], to: ["The Council"],
                          blocks: (1...paragraphs).map { _ in .paragraph(String(repeating: "We write to ask the council to fund the reading room. ", count: 4)) })
        }
        let near = try await renderer.lay(letter(15), pictures: [:], limit: 1)
        XCTAssertEqual(near.raw.pages, 1, "a letter just over a page is set tighter to fit")
        XCTAssertGreaterThan(near.layout.tightened, 0)
        XCTAssertGreaterThanOrEqual(near.layout.size, QuillLayout.floorSize)
        XCTAssertTrue(near.findings.isEmpty, "\(near.findings)")

        let far = try await renderer.lay(letter(40), pictures: [:], limit: 1)
        XCTAssertGreaterThan(far.raw.pages, 1)
        let finding = try XCTUnwrap(far.findings.first { $0.kind == .pages })
        XCTAssertTrue(finding.sentence.contains("must be 1: cut about"), finding.sentence)
        XCTAssertGreaterThanOrEqual(far.layout.size, QuillLayout.floorSize, "never under the floor")
    }

    /// Every form's first page lays out, and a one-page document carries no page numbers.
    func testEveryFormLaysOut() async throws {
        let renderer = QuillRenderer()
        for form in QuillForm.allCases {
            let document = QuillDocument(form: form, title: "Spring Fair", subtitle: "Saturday on the green", author: "Ada Moss", date: "May 3",
                                         from: ["ada@example.com", "555 0100"], to: ["Parents and staff"],
                                         blocks: [.heading("Details"), .paragraph("Stalls open at **ten**."),
                                                  QuillBlock(.fields, fields: [.init(label: "Name"), .init(label: "Stall", value: "Cakes")]),
                                                  QuillBlock(.signature, text: "Ada Moss", by: "Chair")])
            let paged = try await renderer.lay(document, pictures: [:], limit: nil)
            XCTAssertEqual(paged.raw.pages, 1, "\(form)")
            if let dir = ProcessInfo.processInfo.environment["QUILL_KEEP"] {
                try? FileManager.default.createDirectory(atPath: dir + "/forms", withIntermediateDirectories: true)
                try? QuillPDFWriter.write(paged.pages, document: document).write(to: URL(fileURLWithPath: dir + "/forms/\(form.rawValue).pdf"))
            }
            let text = try XCTUnwrap(PDFDocument(data: paged.pages[0])?.string, "\(form)")
            XCTAssertTrue(text.contains("Stalls open at ten"), "\(form): \(text.prefix(120))")
            XCTAssertFalse(text.contains("1 of 1"), "\(form): no page number on a single page")
        }
    }
}
